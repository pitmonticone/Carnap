{-#LANGUAGE FlexibleContexts, AllowAmbiguousTypes #-}
module Carnap.Languages.Util.GenericParsers
where

import Carnap.Core.Data.AbstractSyntaxDataTypes
import Carnap.Languages.Util.LanguageClasses
import Text.Parsec
import Data.Typeable(Typeable)
import Data.List (findIndex)

listToTry :: [ParsecT s u m a] -> ParsecT s u m a
listToTry (x:xs) = foldr (\y -> (<|>) (try y)) (try x) xs

stringsToTry :: Stream s m Char => [String] -> b -> ParsecT s u m b
stringsToTry l op = do spaces
                       _ <- listToTry (map string l)
                       spaces
                       return op

--------------------------------------------------------
--Operators
--------------------------------------------------------

parseAnd :: (Monad m, BooleanLanguage l) => ParsecT String u m (l -> l -> l)
parseAnd = stringsToTry ["/\\", "∧", "^", "&", "and"] land

parseOr :: (BooleanLanguage l, Monad m) => ParsecT String u m (l -> l -> l)
parseOr = stringsToTry ["\\/", "∨", "v", "|", "or"] lor

parseIf :: (BooleanLanguage l, Monad m) => ParsecT String u m (l -> l -> l)
parseIf = stringsToTry [ "=>", "->", ">", "→", "only if"] lif

parseIff :: (BooleanLanguage l, Monad m) => ParsecT String u m (l -> l -> l)
parseIff = stringsToTry [ "<=>",  "<->", "<>", "↔", "if and only if"] liff

parseNeg :: (BooleanLanguage l, Monad m) => ParsecT String u m (l -> l)
parseNeg = do spaces
              _ <- string "-" <|> string "~" <|> string "¬" <|> string "not "
              return lneg

parseNec :: (ModalLanguage l, Monad m) => ParsecT String u m (l -> l)
parseNec = do spaces
              _ <- string "[]" <|> string "□"
              return nec

parsePos :: (ModalLanguage l, Monad m) => ParsecT String u m (l -> l)
parsePos = do spaces
              _ <- string "<>" <|> string "◇"
              return pos

--------------------------------------------------------
--Predicates and Sentences
--------------------------------------------------------

atomicSentenceParser :: (IndexedPropLanguage l, Monad m) => ParsecT String u m l
atomicSentenceParser = try parseNumbered <|> parseUnnumbered
        where parseUnnumbered = do c <- oneOf "PQRSTUVW"
                                   let Just n = findIndex (== c) "_PQRSTUVW"
                                   return $ pn (-1 * n)
              parseNumbered = do char 'P'
                                 char '_'
                                 n <- number
                                 return $ pn n

schemevarParser :: 
    ( IndexedSchemePropLanguage l
    , Monad m
    ) => ParsecT String u m l
schemevarParser = try parseNumbered <|> parseUnnumbered
    where parseUnnumbered = do c <- oneOf "_φψχθγζξ"
                               let Just n = findIndex (== c) "_φψχθγζξ"
                               return $ phin (-1 * n)
          parseNumbered = do string "Phi" <|> string "φ"
                             char '_'
                             n <- number <?> "number"
                             return $ phin n

unaryOpParser :: (Monad m) => [ParsecT String u m (l -> l)] -> ParsecT String u m l ->  ParsecT String u m l
unaryOpParser ops recur = do n <- listToTry ops
                             f <- recur
                             return $ n f

equalsParser :: 
    ( EqLanguage l t
    , Monad m
    ) => ParsecT String u m t -> ParsecT String u m l
equalsParser parseTerm = do t1 <- parseTerm
                            spaces
                            _ <- char '='
                            spaces
                            t2 <- parseTerm
                            return $ equals t1 t2

--TODO: This would need an optional "^m" following P, if we're going to
--achive read . show = id; the code overlap with the next function could be
--significantly reduced.
molecularSentenceParser :: 
    ( PolyadicPredicateLanguage (FixLang lex) arg ret
    , Incrementable lex arg
    , Monad m
    , Typeable ret
    , Typeable arg
    ) => ParsecT String u m (FixLang lex arg) -> ParsecT String u m (FixLang lex ret)
molecularSentenceParser parseTerm = try parseNumbered <|> parseUnnumbered
    where parseUnnumbered = do c <- oneOf "FGHIJKLMNO"
                               let Just n = findIndex (== c) "_FGHIJKLMNO"
                               char '(' *> argParser parseTerm (ppn (-1 * n) AOne)
          parseNumbered = do string "F_"
                             n <- number
                             char '(' *> argParser parseTerm (ppn n AOne)

quantifiedSentenceParser :: 
    ( QuantLanguage (FixLang lex f) (FixLang lex t)
    , BoundVars lex
    , Show (FixLang lex t)
    , Monad m
    ) => ParsecT String u m (FixLang lex t) -> ParsecT String u m (FixLang lex f) 
            -> ParsecT String u m (FixLang lex f)
quantifiedSentenceParser parseFreeVar formulaParser =
        do s <- oneOf "AE∀∃"
           v <- parseFreeVar
           f <- formulaParser
           let bf = \x -> subBoundVar v x f
               --partially applied, returning a function
           return $ if s `elem` "A∀" then lall (show v) bf else lsome (show v) bf
               --which we bind

--------------------------------------------------------
--Terms
--------------------------------------------------------

molecularTermParser ::     
    ( PolyadicFunctionLanguage (FixLang lex) arg ret
    , Incrementable lex arg
    , Monad m
    , Typeable ret
    , Typeable arg
    ) => ParsecT String u m (FixLang lex arg) -> ParsecT String u m (FixLang lex ret)
molecularTermParser parseTerm = try parseNumbered <|> parseUnnumbered
    where parseNumbered = do string "f_"
                             n <- number
                             char '(' *> argParser parseTerm (pfn n AOne)
          parseUnnumbered = do c <- oneOf "fgh"
                               let Just n = findIndex (== c) "_fgh"
                               char '(' *> argParser parseTerm (pfn (-1 * n) AOne)

parseConstant :: 
    ( IndexedConstantLanguage (FixLang lex ret)
    , Typeable ret
    , Monad m
    ) => ParsecT String u m (FixLang lex ret)
parseConstant = try parseNumbered <|> parseUnnumbered
    where parseUnnumbered = do c <- oneOf "abcde"
                               let Just n = findIndex (== c) "_abcde"
                               return $ cn (-1 * n)
          parseNumbered  = do _ <- string "c_"
                              n <- number
                              return $ cn n

--------------------------------------------------------
--Structural Elements
--------------------------------------------------------

parenParser :: 
    (BooleanLanguage l, Monad m) => ParsecT String u m l -> ParsecT String u m l
parenParser recur = char '(' *> recur <* char ')'


number :: Monad m => ParsecT String u m Int
number = do valence <- option "+" (string "-") 
            ds <- many1 digit; 
            if valence == "+" 
                then return (read ds) 
                else return (read ds * (-1))

--------------------------------------------------------
--Helper functions
--------------------------------------------------------

argParser :: 
    ( Typeable b
    , Typeable t2
    , Incrementable lex t2
    , Monad m) => ParsecT String u m (FixLang lex t2) -> FixLang lex (t2 -> b) 
            -> ParsecT String u m (FixLang lex b)
argParser pt p = do t <- pt
                    incrementHead pt p t
                        <|> char ')' *> return (p :!$: t)

incrementHead :: 
    ( Monad m
    , Typeable t2
    , Typeable b
    , Incrementable lex t2
    ) => ParsecT String u m (FixLang lex t2) -> FixLang lex (t2 -> b) -> FixLang lex t2 
        -> ParsecT String u m (FixLang lex b)
incrementHead pt p t = do char ','
                          case incBody p of
                               Just p' -> argParser pt (p' :!$: t)
                               Nothing -> fail "Weird error with function"
