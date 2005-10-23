module Action where

import Config
import Error

import Control.Monad.State
import Control.Monad.Error
import System.IO
import System.Environment

type HPAction = ErrorT HackPortError (StateT HPState IO)

data HPState = HPState
	{ config :: Config
	, indention :: Int
	}

verbose :: HPAction a -> (String,a->String) -> HPAction a
verbose action (premsg,postmsg) = do
	echoIndent
	echo premsg
	flush
	res <- indent action
	echoIndent
	echoLn (postmsg res)
	return res

sayNormal :: HPAction a -> (String,a->String) -> HPAction a
sayNormal action strs = do
	cfg <- getCfg
	case verbosity cfg of
		Silent -> action
		_ -> action `verbose` strs

sayDebug :: HPAction a -> (String,a->String) -> HPAction a
sayDebug action strs = do
	cfg <- getCfg
	case verbosity cfg of
		Debug -> action `verbose` strs
		_ -> action

info :: String -> HPAction ()
info str = do
	cfg <- getCfg
	case verbosity cfg of
		Silent -> return ()
		_ -> echoLn str

getCfg :: HPAction Config
getCfg = gets config

setPortageTree :: Maybe String -> HPAction ()
setPortageTree mt = modify $ \hps -> 
	hps { config = (config hps) { portageTree = mt } }

lessIndent :: HPAction ()
lessIndent = modify $ \s -> s { indention = indention s - 1 }

moreIndent :: HPAction ()
moreIndent = modify $ \s -> s { indention = indention s + 1 }

echoIndent :: HPAction ()
echoIndent = do
	ind <- gets indention
	echo (replicate ind '\t')

indent :: HPAction a -> HPAction a
indent action = do
	moreIndent
	res <- action
	lessIndent
	return res

echo :: String -> HPAction ()
echo str = liftIO $ hPutStr stderr str

flush :: HPAction ()
flush = liftIO (hFlush stderr)

echoLn :: String -> HPAction ()
echoLn str = echoIndent >> echo str >> liftIO (hPutChar stderr '\n')

loadConfig :: HPAction OperationMode
loadConfig = do
	args <- liftIO getArgs
	case parseConfig args of
		Left errmsg -> throwError (ArgumentError errmsg)
		Right (cfg,opmode) -> do
			modify $ \s -> s { config = cfg }
			return opmode

performHPAction :: HPAction a -> IO ()
performHPAction action = do
	res <- evalStateT (runErrorT action) (HPState defaultConfig 0)
	case res of
		Left err -> hPutStr stderr (hackPortShowError err)
		Right _ -> return ()