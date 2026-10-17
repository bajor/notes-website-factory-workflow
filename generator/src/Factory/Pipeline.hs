{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}

-- | The software factory's imperative shell.
--
-- This is the only module that decides which files to read and write. The
-- parser, interpreter, and validator receive explicit values, so tests can
-- run them without hidden filesystem access.
module Factory.Pipeline
  ( discoverSingleSource
  , outputCompanionPaths
  , runCommand
  , sourceAt
  , validateOutputPath
  ) where

import Control.Exception (IOException, throwIO, try)
import Control.Monad (forM, when)
import Data.List (sort)
import Data.Text (Text)
import Factory.Domain
import Factory.Evaluation (EvaluationResult (..), Reference (..), runVisualEvaluation)
import Factory.Pdf (ParsedPdf (..), PdfSummary (..), parsePdf)
import Factory.Site (validateScene, writeSite)
import Factory.Svg (SvgBoard (..), ValidatedSvg (..), readSvg, svgScene)
import System.Directory
  ( canonicalizePath
  , createDirectoryIfMissing
  , doesDirectoryExist
  , doesFileExist
  , doesPathExist
  , listDirectory
  , makeAbsolute
  , pathIsSymbolicLink
  , removePathForcibly
  , renameDirectory
  )
import System.Environment (getArgs)
import System.Exit (exitFailure)
import System.FilePath (dropTrailingPathSeparator, isAbsolute, makeRelative, normalise, splitDirectories, takeDirectory, takeExtension, takeFileName, (</>))
import System.IO.Error (isDoesNotExistError)
import qualified Data.Text as Text
import qualified Data.Text.IO as Text

runCommand :: IO ()
runCommand = do
  arguments <- getArgs
  result <- case arguments of
    ["inspect", sourceRoot, workDirectory] -> inspectRepository sourceRoot workDirectory
    ["build", sourceRoot, templateDirectory, outputDirectory, rawTitle] ->
      withSiteTitle rawTitle (buildRepository sourceRoot templateDirectory outputDirectory)
    ["evaluate", sourceRoot, templateDirectory, outputDirectory, reportDirectory, rawTitle] ->
      withSiteTitle rawTitle (evaluateRepository sourceRoot templateDirectory outputDirectory reportDirectory)
    _ -> pure (Left (IoError "usage: notes-site inspect SOURCE WORK | build SOURCE TEMPLATES DIST TITLE | evaluate SOURCE TEMPLATES DIST REPORT TITLE"))
  case result of
    Left buildError -> Text.putStrLn ("ERROR: " <> renderError buildError) >> exitFailure
    Right message -> Text.putStrLn message

discoverSingleSource :: FilePath -> IO (Either BuildError Source)
discoverSingleSource sourceRoot = do
  result <- try (collectSources sourceRoot)
  pure $ case result of
    Left exception -> Left (IoError (Text.pack (show (exception :: IOException))))
    Right [source] -> Right source
    Right sources -> Left (SourceCountError (length sources))

sourceAt :: FilePath -> Maybe Source
sourceAt path = case map asciiLower (takeExtension path) of
  ".pdf" -> Just (PdfSource path)
  ".svg" -> Just (SvgSource path)
  _ -> Nothing

sourcePath :: Source -> FilePath
sourcePath source = case source of
  PdfSource path -> path
  SvgSource path -> path

-- | Read the source into an unvalidated scene and a summary, writing any raster assets.
loadSource :: Source -> FilePath -> IO (Either BuildError (Scene 'Unvalidated, Text))
loadSource source assetDirectory = case source of
  PdfSource pdf -> fmap (\parsed -> (parsedScene parsed, pdfSummaryText pdf (parsedSummary parsed))) <$> parsePdf pdf assetDirectory
  SvgSource svg -> fmap (\validated -> (svgScene validated, svgSummaryText svg (validatedBoard validated))) <$> readSvg svg

evaluationReference :: Source -> IO (Either BuildError Reference)
evaluationReference source = case source of
  PdfSource pdf -> pure (Right (PopplerReference pdf))
  SvgSource svg -> fmap (\(ValidatedSvg (SvgBoard width height) _) -> BrowserReference svg width height) <$> readSvg svg

inspectRepository :: FilePath -> FilePath -> IO (Either BuildError Text)
inspectRepository sourceRoot workDirectory = do
  absoluteSource <- canonicalizePath sourceRoot
  preparedScratch <- prepareRemovalPath (workDirectory </> "inspect-assets")
  case preparedScratch >>= validatePreparedPath [absoluteSource] of
    Left buildError -> pure (Left buildError)
    Right scratch -> withSingleSource absoluteSource $ \source -> do
      resetDirectory scratch
      loaded <- loadSource source scratch
      removePathForcibly scratch
      pure (snd <$> loaded)

buildRepository :: FilePath -> FilePath -> FilePath -> SiteTitle -> IO (Either BuildError Text)
buildRepository sourceRoot templateDirectory outputDirectory title = do
  absoluteSource <- canonicalizePath sourceRoot
  absoluteTemplates <- canonicalizePath templateDirectory
  prepared <- prepareOutputDirectories outputDirectory
  case prepared of
    Left buildError -> pure (Left buildError)
    Right (absoluteOutput, stagingDirectory, backupDirectory) ->
      case traverse (validatePreparedPath [absoluteSource, absoluteTemplates]) [absoluteOutput, stagingDirectory, backupDirectory] of
        Left buildError -> pure (Left buildError)
        Right _ -> buildToStaging absoluteSource absoluteTemplates absoluteOutput stagingDirectory backupDirectory title

buildToStaging :: FilePath -> FilePath -> FilePath -> FilePath -> FilePath -> SiteTitle -> IO (Either BuildError Text)
buildToStaging absoluteSource absoluteTemplates absoluteOutput stagingDirectory backupDirectory title =
  withSingleSource absoluteSource $ \source -> do
    resetDirectory stagingDirectory
    loaded <- loadSource source (stagingDirectory </> "assets")
    case loaded of
      Left buildError -> removePathForcibly stagingDirectory >> pure (Left buildError)
      Right (unvalidated, summary) -> case validateScene unvalidated of
        Left buildError -> removePathForcibly stagingDirectory >> pure (Left buildError)
        Right scene -> do
          writeSite absoluteTemplates stagingDirectory title scene
          promoted <- promoteDirectory stagingDirectory absoluteOutput backupDirectory
          pure $ case promoted of
            Left buildError -> Left buildError
            Right () -> Right ("Built JavaScript scene from " <> Text.pack (takeFileName (sourcePath source)) <> "\n" <> summary)

evaluateRepository :: FilePath -> FilePath -> FilePath -> FilePath -> SiteTitle -> IO (Either BuildError Text)
evaluateRepository sourceRoot templateDirectory outputDirectory reportDirectory title = do
  absoluteSource <- canonicalizePath sourceRoot
  absoluteTemplates <- canonicalizePath templateDirectory
  preparedOutput <- prepareOutputDirectories outputDirectory
  preparedReport <- prepareRemovalPath reportDirectory
  case (,) <$> preparedOutput <*> preparedReport of
    Left buildError -> pure (Left buildError)
    Right ((absoluteOutput, stagingDirectory, backupDirectory), absoluteReport) ->
      case
          traverse (validatePreparedPath [absoluteSource, absoluteTemplates, absoluteReport]) [absoluteOutput, stagingDirectory, backupDirectory]
            >> validatePreparedPath [absoluteSource, absoluteTemplates] absoluteReport
        of
          Left buildError -> pure (Left buildError)
          Right _ -> do
            built <- buildRepository absoluteSource absoluteTemplates absoluteOutput title
            case built of
              Left buildError -> pure (Left buildError)
              Right _ -> do
                discovered <- discoverSingleSource absoluteSource
                reference <- either (pure . Left) evaluationReference discovered
                case reference of
                  Left buildError -> pure (Left buildError)
                  Right oracle -> do
                    evaluation <- runVisualEvaluation oracle absoluteOutput absoluteReport
                    pure $ case evaluation of
                      Left buildError -> Left buildError
                      Right result
                        | evaluationPassed result -> Right (evaluationText "Evaluation passed." absoluteReport result)
                        | otherwise -> Left (EvaluationError (evaluationText "Evaluation did not meet the required thresholds." absoluteReport result))

withSiteTitle :: String -> (SiteTitle -> IO (Either BuildError Text)) -> IO (Either BuildError Text)
withSiteTitle rawTitle action = either (pure . Left) action (mkSiteTitle (Text.pack rawTitle))

withSingleSource :: FilePath -> (Source -> IO (Either BuildError Text)) -> IO (Either BuildError Text)
withSingleSource root action = discoverSingleSource root >>= either (pure . Left) action

collectSources :: FilePath -> IO [Source]
collectSources directory = do
  entries <- sort <$> listDirectory directory
  fmap concat . forM entries $ \entry -> do
    let path = directory </> entry
    isDirectory <- doesDirectoryExist path
    isFile <- doesFileExist path
    isSymbolicLink <- pathIsSymbolicLink path
    if isDirectory && not isSymbolicLink && entry `notElem` ignoredDirectories
      then collectSources path
      else pure [source | isFile && not isSymbolicLink, Just source <- [sourceAt path]]

ignoredDirectories :: [FilePath]
ignoredDirectories = [".git", "build", "dist", "dist.building", "dist.previous", "dist-newstyle", "node_modules"]

resetDirectory :: FilePath -> IO ()
resetDirectory directory = do
  exists <- doesPathExist directory
  if exists then removePathForcibly directory else pure ()
  createDirectoryIfMissing True directory

promoteDirectory :: FilePath -> FilePath -> FilePath -> IO (Either BuildError ())
promoteDirectory stagingDirectory outputDirectory backupDirectory = do
  result <- tryIo $ do
    recoverInterruptedPromotion outputDirectory backupDirectory
    renameDirectory outputDirectory backupDirectory
    promoted <- tryIo (renameDirectory stagingDirectory outputDirectory)
    case promoted of
      Left exception -> renameDirectory backupDirectory outputDirectory >> throwIO exception
      Right () -> removePathForcibly backupDirectory
  pure $ case result of
    Left exception -> Left (IoError (Text.pack (show exception)))
    Right () -> Right ()

recoverInterruptedPromotion :: FilePath -> FilePath -> IO ()
recoverInterruptedPromotion outputDirectory backupDirectory = do
  outputExists <- doesPathExist outputDirectory
  backupExists <- doesPathExist backupDirectory
  when (backupExists && outputExists) (removePathForcibly backupDirectory)
  when (backupExists && not outputExists) (renameDirectory backupDirectory outputDirectory)
  finalOutputExists <- doesPathExist outputDirectory
  if finalOutputExists then pure () else createDirectoryIfMissing True outputDirectory

prepareOutputDirectories :: FilePath -> IO (Either BuildError (FilePath, FilePath, FilePath))
prepareOutputDirectories outputDirectory = do
  absoluteOutput <- makeAbsolute outputDirectory
  let (outputPath, stagingPath, backupPath) = outputCompanionPaths absoluteOutput
  output <- prepareRemovalPath outputPath
  staging <- prepareRemovalPath stagingPath
  backup <- prepareRemovalPath backupPath
  pure ((,,) <$> output <*> staging <*> backup)

outputCompanionPaths :: FilePath -> (FilePath, FilePath, FilePath)
outputCompanionPaths outputDirectory =
  (normalized, normalized <> ".building", normalized <> ".previous")
  where
    normalized = dropTrailingPathSeparator (normalise outputDirectory)

prepareRemovalPath :: FilePath -> IO (Either BuildError FilePath)
prepareRemovalPath = canonicalizeRemovalPath . normalise

canonicalizeRemovalPath :: FilePath -> IO (Either BuildError FilePath)
canonicalizeRemovalPath path = do
  symbolicLink <- tryIo (pathIsSymbolicLink path)
  case symbolicLink of
    Right True -> pure (Left (IoError "removable path targets and unresolved parents must not be symbolic links"))
    Right False -> Right <$> canonicalizePath path
    Left exception
      | isDoesNotExistError exception -> do
          parent <- canonicalizeRemovalPath (takeDirectory path)
          pure ((</> takeFileName path) <$> parent)
      | otherwise -> pure (Left (IoError (Text.pack (show exception))))

tryIo :: IO value -> IO (Either IOException value)
tryIo = try

-- | Reject removable locations that overlap protected input files.
validateOutputPath :: FilePath -> FilePath -> Either BuildError ()
validateOutputPath protectedRoot outputDirectory
  | pathsOverlap = Left (IoError "a removable path must not overlap a protected root")
  | otherwise = Right ()
  where
    pathsOverlap = contains protectedRoot outputDirectory || contains outputDirectory protectedRoot
    contains parent child = isDescendant (makeRelative (normalise parent) (normalise child))
    isDescendant "." = True
    isDescendant path
      | isAbsolute path = False
      | otherwise = case splitDirectories path of
          ".." : _ -> False
          _ -> True

validatePreparedPath :: [FilePath] -> FilePath -> Either BuildError FilePath
validatePreparedPath protectedRoots path = path <$ traverse (`validateOutputPath` path) protectedRoots

pdfSummaryText :: FilePath -> PdfSummary -> Text
pdfSummaryText pdf summary =
  Text.unlines
    [ "File: " <> Text.pack (takeFileName pdf)
    , "Format: PDF"
    , "Pages: " <> numberText (summaryPageCount summary)
    , "Board: " <> decimalText (summaryWidth summary) <> " x " <> decimalText (summaryHeight summary) <> " pt"
    , "Operators: " <> numberText (summaryOperatorCount summary)
    , "Images: " <> numberText (summaryImageCount summary)
    , "Vector artworks: " <> numberText (summaryVectorCount summary)
    , "Raster images: " <> numberText (summaryRasterCount summary)
    , "Links: " <> numberText (summaryLinkCount summary)
    ]

svgSummaryText :: FilePath -> SvgBoard -> Text
svgSummaryText svg (SvgBoard width height) =
  Text.unlines
    [ "File: " <> Text.pack (takeFileName svg)
    , "Format: SVG"
    , "Board: " <> decimalText (unCoordinate width) <> " x " <> decimalText (unCoordinate height) <> " px"
    ]

renderError :: BuildError -> Text
renderError buildError = case buildError of
  SourceCountError count -> "expected exactly one PDF or SVG source file, found " <> numberText count
  PageCountError count -> "PDF must contain exactly one page, found " <> numberText count
  PdfStructureError message -> "invalid PDF structure: " <> message
  UnsupportedOperator message -> "unsupported PDF operator: " <> message
  UnsupportedImage message -> "unsupported PDF image: " <> message
  GraphicsStateError message -> "invalid PDF graphics state: " <> message
  InvalidScene message -> "invalid generated scene: " <> message
  InvalidUrl message -> "invalid PDF link: " <> message
  InvalidSvg message -> "invalid SVG: " <> message
  UnsupportedSvg message -> "unsupported SVG content: " <> message
  InvalidSiteTitle message -> "invalid site title: " <> message
  EvaluationError message -> "evaluation failed: " <> message
  IoError message -> message

numberText :: Show value => value -> Text
numberText = Text.pack . show

decimalText :: Double -> Text
decimalText = Text.pack . show

asciiLower :: Char -> Char
asciiLower character
  | 'A' <= character && character <= 'Z' = toEnum (fromEnum character + 32)
  | otherwise = character

evaluationText :: Text -> FilePath -> EvaluationResult -> Text
evaluationText statusMessage reportDirectory result =
  Text.unlines
    [ statusMessage
    , "Mean normalized channel error: " <> decimalText (evaluationMeanError result)
    , "Pixels within tolerance: " <> decimalText (evaluationPixelsWithinTolerance result)
    , "Generated/reference ink ratio: " <> decimalText (evaluationInkRatio result)
    , "Evidence: " <> Text.pack (reportDirectory </> "report.html")
    ]
