
{-# LANGUAGE DeriveGeneric, DeriveAnyClass, TypeApplications, QuasiQuotes, TypeOperators #-}
{-# LANGUAGE DataKinds, TypeFamilies #-}

module Test.Language.Souffle.ExperimentalSpec
  ( module Test.Language.Souffle.ExperimentalSpec
  ) where

import Prelude hiding (not)
import Test.Hspec
import GHC.Generics
import Control.Applicative
import Data.Int
import Language.Souffle.Experimental
import Language.Souffle.Class
import NeatInterpolation


data Point = Point { x :: Int32, y :: Int32 }
  deriving (Generic, Marshal)

data IntFact = IntFact Int32
  deriving (Generic, Marshal)

data Triple = Triple String Int32 String
  deriving (Generic, Marshal)

data Edge = Edge String String
  deriving (Generic, Marshal)

data Reachable = Reachable String String
  deriving (Generic, Marshal)

instance Fact Point where factName = const "point"
instance Fact IntFact where factName = const "intfact"
instance Fact Triple where factName = const "triple"
instance Fact Edge where factName = const "edge"
instance Fact Reachable where factName = const "reachable"


spec :: Spec
spec = fdescribe "Souffle DSL" $ parallel $ do
  describe "code generation" $ parallel $ do
    let prog ==> txt = render (runDSL prog) `shouldBe` (txt <> "\n")

    it "can render an empty program" $ do
      render (runDSL $ pure ()) `shouldBe` ""

    it "can render a program with an input type definition" $ do
      let prog = do
            Predicate _ <- typeDef @Edge Input
            pure ()
      prog ==> [text|
        .decl edge(t1: symbol, t2: symbol)
        .input edge
        |]

    it "can render a program with an output type definition" $ do
      let prog = do
            Predicate _ <- typeDef @Edge Output
            pure ()
      prog ==> [text|
        .decl edge(t1: symbol, t2: symbol)
        .output edge
        |]

    it "can render a program with type declared both as in- and output" $ do
      let prog = do
            Predicate _ <- typeDef @Edge InputOutput
            pure ()
      prog ==> [text|
        .decl edge(t1: symbol, t2: symbol)
        .input edge
        .output edge
        |]

    it "renders type declaration based on type info" $ do
      let prog = do
            Predicate _ <- typeDef @IntFact Input
            Predicate _ <- typeDef @Triple Output
            pure ()
      prog ==> [text|
        .decl intfact(t1: number)
        .input intfact
        .decl triple(t1: symbol, t2: number, t3: symbol)
        .output triple
        |]

    it "uses record accessors as attribute names in type declaration if provided" $ do
      let prog = do
            Predicate _ <- typeDef @Point Input
            pure ()
      prog ==> [text|
        .decl point(x: number, y: number)
        .input point
        |]

    it "can render facts" $ do
      let prog = do
            Predicate edge <- typeDef @Edge Input
            Predicate triple <- typeDef @Triple Input
            edge("a", "b")
            triple("cde", 1000, "fgh")
      prog ==> [text|
        .decl edge(t1: symbol, t2: symbol)
        .input edge
        .decl triple(t1: symbol, t2: number, t3: symbol)
        .input triple
        edge("a", "b").
        triple("cde", 1000, "fgh").
        |]

    it "can render a relation with a single rule" $ do
      let prog = do
            Predicate edge <- typeDef @Edge Input
            Predicate reachable <- typeDef @Reachable Output
            a <- var "a"
            b <- var "b"
            reachable(a, b) |- edge(a, b)
      prog ==> [text|
        .decl edge(t1: symbol, t2: symbol)
        .input edge
        .decl reachable(t1: symbol, t2: symbol)
        .output reachable
        reachable(a, b) :-
          edge(a, b).
        |]

    it "can render a relation with multiple rules" $ do
      let prog = do
            Predicate edge <- typeDef @Edge Input
            Predicate reachable <- typeDef @Reachable Output
            a <- var "a"
            b <- var "b"
            reachable(a, b) |- do
              edge(a, a)
              edge(b, b)
              edge(a, b)
      prog ==> [text|
        .decl edge(t1: symbol, t2: symbol)
        .input edge
        .decl reachable(t1: symbol, t2: symbol)
        .output reachable
        reachable(a, b) :-
          edge(a, a),
          edge(b, b),
          edge(a, b).
        |]

    it "can render a relation with a logical or in the rule block" $ do
      let prog = do
            Predicate edge <- typeDef @Edge Input
            Predicate reachable <- typeDef @Reachable Output
            a <- var "a"
            b <- var "b"
            reachable(a, b) |- do
              let rules1 = do
                    edge(a, a)
                    edge(b, b)
                  rules2 = do
                    edge(a, b)
                    edge(b, a)
              rules1 <|> rules2
      prog ==> [text|
        .decl edge(t1: symbol, t2: symbol)
        .input edge
        .decl reachable(t1: symbol, t2: symbol)
        .output reachable
        reachable(a, b) :-
          edge(a, a),
          edge(b, b);
          edge(a, b),
          edge(b, a).
        |]

    it "can render a relation with multiple clauses" $ do
      let prog = do
            Predicate edge <- typeDef @Edge Input
            Predicate reachable <- typeDef @Reachable Output
            a <- var "a"
            b <- var "b"
            c <- var "c"
            reachable(a, b) |- edge(a, b)
            reachable(a, b) |- do
              edge(a, c)
              reachable(c, b)
      prog ==> [text|
        .decl edge(t1: symbol, t2: symbol)
        .input edge
        .decl reachable(t1: symbol, t2: symbol)
        .output reachable
        reachable(a, b) :-
          edge(a, b).
        reachable(a, b) :-
          edge(a, c),
          reachable(c, b).
        |]

    it "can render a mix of and- and or- clauses correctly" $ do
      let prog = do
            Predicate edge <- typeDef @Edge Input
            Predicate reachable <- typeDef @Reachable Output
            a <- var "a"
            b <- var "b"
            c <- var "c"
            reachable(a, b) |- do
              edge(a, c) <|> edge(a, b)
              reachable(c, b)
      prog ==> [text|
        .decl edge(t1: symbol, t2: symbol)
        .input edge
        .decl reachable(t1: symbol, t2: symbol)
        .output reachable
        reachable(a, b) :-
          (edge(a, c);
          edge(a, b)),
          reachable(c, b).
        |]

    it "allows generically describing predicate relations" $ do
      -- NOTE: type signature not required, but it results in more clear type errors
      -- and can serve as documentation.
      let transitive :: forall p1 p2 t. Structure p1 ~ Structure p2
                     => Structure p1 ~ '[t, t]
                     => Predicate p1 -> Predicate p2 -> DSL 'Definition ()
          transitive (Predicate p1) (Predicate p2) = do
            a <- var "a"
            b <- var "b"
            c <- var "c"
            p1(a, b) |- p2(a, b)
            p1(a, b) |- do
              p2(a, c)
              p1(c, b)
          prog = do
            edge <- typeDef @Edge Input
            reachable <- typeDef @Reachable Output
            transitive reachable edge
      prog ==> [text|
        .decl edge(t1: symbol, t2: symbol)
        .input edge
        .decl reachable(t1: symbol, t2: symbol)
        .output reachable
        reachable(a, b) :-
          edge(a, b).
        reachable(a, b) :-
          edge(a, c),
          reachable(c, b).
        |]

    it "can render logical negation in rule block" $ do
      let prog = do
            Predicate edge <- typeDef @Edge Input
            Predicate triple <- typeDef @Triple Output
            a <- var "a"
            b <- var "b"
            c <- var "c"
            triple(a, b, c) |- do
              not $ edge(a,c)
            triple(a, b, c) |- do
              not $ do
                edge(a,a)
                edge(c,c)
            triple(a, b, c) |- do
              not $ edge(a,a) <|> edge(c,c)
            triple(a, b, c) |- do
              not $ not $ edge(a,a)
      prog ==> [text|
        .decl edge(t1: symbol, t2: symbol)
        .input edge
        .decl triple(t1: symbol, t2: number, t3: symbol)
        .output triple
        triple(a, b, c) :-
          !edge(a, c).
        triple(a, b, c) :-
          !(edge(a, a),
          edge(c, c)).
        triple(a, b, c) :-
          !(edge(a, a);
          edge(c, c)).
        triple(a, b, c) :-
          !!edge(a, a).
        |]

    it "generates unique var names to avoid name collisions" $ do
      let prog = do
            Predicate edge <- typeDef @Edge Input
            Predicate reachable <- typeDef @Reachable Output
            a <- var "a"
            a' <- var "a"
            reachable(a, a') |- edge(a, a')
      prog ==> [text|
        .decl edge(t1: symbol, t2: symbol)
        .input edge
        .decl reachable(t1: symbol, t2: symbol)
        .output reachable
        reachable(a, a_1) :-
          edge(a, a_1).
        |]

