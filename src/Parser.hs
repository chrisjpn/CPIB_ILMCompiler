module Parser ( readExpr, IMLVal, IMLType, IMLFlowMode, IMLChangeMode ) where

import Text.ParserCombinators.Parsec hiding (spaces)
import Text.Parsec.Token
import System.Environment

data IMLType = Int64
            deriving Show

data IMLFlowMode = In | Out
            deriving Show

data IMLChangeMode = Const | Mutable
            deriving Show

data IMLSign = Plus | Minus | Not
            deriving Show

data IMLLiteral = IMLBool Bool | IMLInt Int
            deriving Show

data IMLVal = Program [IMLVal] IMLVal
            | Ident String
            | IdentDeclaration (Maybe IMLFlowMode) IMLChangeMode IMLVal IMLType
            | IdentFactor (Maybe IMLVal)
            | BoolOpr IMLVal IMLVal
            | RelOpr IMLVal IMLVal
            | AddOpr IMLVal IMLVal
            | MultOpr IMLVal IMLVal
            | SignedVal IMLSign IMLVal
            | Literal IMLLiteral
            | Init
            | ExprList [IMLVal]
            | Message String
            deriving Show

readExpr :: String -> IMLVal
readExpr input = case parse parseProgram "Hambbe" input of
    Left err -> Message $ "fuck you: " ++ show err
    Right val -> val

spaces :: Parser ()
spaces = skipMany space

spaces1 :: Parser ()
spaces1 = skipMany1 space

identStartChars :: String
identStartChars = ['a'..'z']++['A'..'Z']++"_"

identChars :: String
identChars = identStartChars++['0'..'9']

parseProgram :: Parser IMLVal
parseProgram = parseProgram1

parseProgram1 :: Parser IMLVal
parseProgram1 = do
    string "program"
    spaces
    name <- parseIdent
    params <- option [] parseProgParamList
    spaces
    char '{'
    spaces 
    x <- many (noneOf "}")
    spaces
    char '}'
    return $ Program params name

parseProgParamList :: Parser [IMLVal]
parseProgParamList = do
    char '('
    spaces
    params <- parseProgParam `sepBy` (string ",")
    spaces
    char ')'
    return params

parseProgParam :: Parser IMLVal
parseProgParam = do
    spaces
    flowMode <- optionMaybe parseFlowMode
    spaces
    changeMode <- parseChangeMode
    spaces
    (identName, identType) <- parseTypedIdent
    return $ IdentDeclaration flowMode changeMode identName identType

parseFlowMode :: Parser IMLFlowMode
parseFlowMode = do 
    (string "in")
    return In
    <|> do 
    (string "out")
    return Out

parseChangeMode :: Parser IMLChangeMode
parseChangeMode = option Mutable parseConst

parseConst :: Parser IMLChangeMode
parseConst = do 
    string "const"
    return Const

parseTypedIdent :: Parser (IMLVal, IMLType)
parseTypedIdent = do
    identName <- parseIdent
    spaces
    char ':'
    spaces
    identType <- parseType
    return (identName, identType)

parseType :: Parser IMLType
parseType = do
    string "int64"
    return Int64

parseIdent :: Parser IMLVal
parseIdent = do
                head <- oneOf identStartChars
                tail <- many $ oneOf identChars
                return $ Ident (head : tail)


parseFactor :: Parser IMLVal
parseFactor = do
    spaces
    try string "true"
    return $ Literal $ IMLBool True
    <|> do
    try string "false"
    return $ Literal $ IMLBool False
    <|> do
    literal <- try many1 digit
    return $ Literal $ IMLInt literal
    <|> do
    ident <- parseIdent
    spaces
    identAddition <- optionMaybe (choice [ parseInit, parseExprList ])
    return $ IdentFactor identAddition
    <|> do
    monadicOpr <- parseMonadicOpr
    spaces
    factor <- parseFactor
    return $ SignedVal monadicOpr factor
    <|> do
    char '('
    spaces
    expr <- parseExpr
    spaces
    char ')'
    return expr

parseInit :: Parsec IMLVal
parseInit = do
    spaces
    string "init"
    return Init

parseExprList :: Parser IMLVal
parseExprList  = do
    spaces
    char '('
    spaces
    exprList <- option [] parseExprListInner
    spaces
    char ')'
    return $ ExprList exprList

parseExprListInner :: Parser [IMLVal]
parseExprListInner  = do
    expressions <- parseExpr `sepBy` (string ",")
    return expressions

parseMonadicOpr :: Parser IMLSign
parseMonadicOpr = do
    spaces
    char '!'
    return Not
    <|> do
    spaces
    char '+'
    return $ Plus
    <|> do
    spaces
    char '-'
    return $ Minus


main :: IO()
main = print . readExpr $ "program HambbeKoenig {}"