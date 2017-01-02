module CodeGenerator
    ( toHaskellVM
    ) where

import Parser
import BaseDecls
import VirtualMachineIO
import Locations
import Data.Array
import Data.Monoid
import CheckedArithmetic

fst3 :: (a, b, c) -> a
fst3 (a, _, _) = a

snd3 :: (a, b, c) -> b
snd3 (_, b, _) = b

thd3 ::  (a, b, c) -> c
thd3 (_, _, c) = c

-- TODO WHY DO WE HAVE TO HAVE SUCH SHIT!!!
fromRight :: Either a b -> b
fromRight (Right b) = b
fromRight _ = error "Not left"

-- Instructions

neg :: Instruction
neg = Neg Int32VmTy mempty

add32, sub32, mult32, divFloor32, eq32, ne32, gt32, ge32, lt32, le32 :: Instruction
add32 = Add Int32VmTy mempty
sub32 = Sub Int32VmTy mempty
mult32 = Mult Int32VmTy mempty
divFloor32 = DivFloor Int32VmTy mempty
eq32 = VirtualMachineIO.Eq Int32VmTy
ne32 = VirtualMachineIO.Ne Int32VmTy
gt32 = VirtualMachineIO.Gt Int32VmTy
ge32 = VirtualMachineIO.Ge Int32VmTy
lt32 = VirtualMachineIO.Lt Int32VmTy
le32 = VirtualMachineIO.Le Int32VmTy

loadAddress :: Int -> Instruction
loadAddress addr = LoadIm IntVmTy (IntVmVal addr)

loadAddrRel :: Int -> Instruction
loadAddrRel = LoadAddrRel

loadIm32 :: Integer -> Instruction
loadIm32 val = LoadIm Int32VmTy (Int32VmVal (fromRight $ fromIntegerToInt32 val))

input32 :: String -> Instruction
input32 name = Input (IntTy 32) mempty name

output32 :: String -> Instruction
output32 name = Output (IntTy 32) name

deref :: Instruction
deref = Deref

call :: CodeAddress -> Instruction
call = Call

store :: Instruction
store = Store

condJump :: CodeAddress -> Instruction
condJump = CondJump

uncondJump :: CodeAddress -> Instruction
uncondJump = UncondJump

-- End Instruction

-- data Scope = Local | Global
-- data Access = Direct | Indirect
type Address = Int

data IdentInfo = Param IMLType IMLFlowMode IMLChangeMode
               | Var IMLType IMLChangeMode
               | Function [Ident] -- parameters
               deriving (Show)

type Ident = (String, Address, IdentInfo)

type Scope = [Ident]

-- stack of scopes
type Enviroment = (CodeAddress, Address, Scope, [Scope]) -- PC, Global, Locals

extractImlType :: IdentInfo -> IMLType
extractImlType (Param imlType _ _) = imlType
extractImlType (CodeGenerator.Var imlType _) = imlType
extractImlType _ = error "cannot extract type of a function"

updatePc :: Enviroment -> Int -> Enviroment
updatePc (pc, sp, global, locals) i = (pc + i, sp, global, locals)

updateSp :: Enviroment -> Int -> Enviroment
updateSp (pc, sp, global, locals) i = (pc, sp + i, global, locals)

-- env pc sp 
updatePcSp :: Enviroment -> Int -> Int -> Enviroment
updatePcSp (pc, sp, global, locals) i k = (pc + i, sp + k, global, locals)

addLocalIdent :: Enviroment -> Ident -> Enviroment
-- TODO Check if Ident already exists => Throw error
addLocalIdent (pc, sp, global, locals) ident = (pc, sp + 1, global, addToLocalScope locals ident)

addLocalScope :: Scope -> Enviroment -> Enviroment 
addLocalScope scope (pc, sp, global, locals) = (pc, sp, global, [scope] ++ locals)  

addToLocalScope :: [Scope] -> Ident -> [Scope]
addToLocalScope (next : rest) ident = (ident : next) : rest 

addToGlobalScope :: Enviroment -> Ident -> Enviroment
addToGlobalScope (pc, sp, global, locals) ident = (pc, sp, ident : global, locals)

removeLocalScope :: Enviroment -> Enviroment
removeLocalScope (pc, sp, global, locals)  = (pc, sp, global, tail locals)

getPc :: Enviroment -> Int
getPc (pc, _, _, _) = pc

getSp :: Enviroment -> Address
getSp (_, sp, _, _) = sp

getLocalScopes :: Enviroment -> [Scope]
getLocalScopes (_, _, _, locals) = locals 

findInScope :: Scope -> String -> Maybe Ident
findInScope [] _ = Nothing
findInScope (next : rest) name = if (fst3 next) == name then Just next else findInScope rest name 

getIdent :: Enviroment -> String -> Ident
getIdent (_, _, global, []) name = case findInScope global name of 
    Nothing -> error $ "Identifier " ++ name ++ " not found!"
    Just a -> a
getIdent (pc, sp, global, next : rest) name = case findInScope next name of
    Nothing -> getIdent (pc, sp, global, rest) name
    Just a -> a

getIdentAddress :: Enviroment -> String -> Address
getIdentAddress a b = (snd3 (getIdent a b))

getIdentInfo :: Enviroment -> String -> IdentInfo
getIdentInfo a b = (thd3 (getIdent a b))

getParams :: IdentInfo -> [Ident]
getParams (Function idents) = idents

toArray :: [a] -> Array Int a
toArray l = array (0, length l - 1)  (zip [0 .. length l - 1] l)

emptyEnv :: Enviroment
emptyEnv = (0, 0, [], [])

toHaskellVM :: IMLVal -> VMProgram
toHaskellVM (Program (Ident name) params functions statements) = (name, toArray codeArray)
    where codeArray = inputInstructions ++ callProgram ++ functionInstructions ++ statementInstructions ++ outputInstructions ++ stopInstructions
          (inputInstructions, inputEndEnv) = generateInputs params emptyEnv
          (functionInstructions, functionEndEnv) = generateFunctions functions (updatePc inputEndEnv 1)
          (callProgram, callProgramEndEnv) = ([ UncondJump $ getPc functionEndEnv ], functionEndEnv)
          (statementInstructions, statementEndEnv) = generateScopeCode statements callProgramEndEnv   
          (outputInstructions, outputEndEnv) = generateOutputs statementEndEnv
          (stopInstructions, _) = ([Stop], updatePc outputEndEnv 1) 
toHaskellVM _ = error "Input is not a Program"

generateOutputs :: Enviroment -> ([Instruction], Enviroment)
generateOutputs env@(pc, sp, global, [] : []) = ([], env)
generateOutputs env@(pc, sp, global, ((name, addr, Param _ Out   _) : rest) : []) = ([loadAddress addr, deref, output32 name] ++ restInstructions, finalEnv)
    where (restInstructions, finalEnv) = generateOutputs (pc + 3, sp - 1, global, [rest])
generateOutputs env@(pc, sp, global, ((name, addr, Param _ InOut _) : rest) : []) = ([loadAddress addr, deref, output32 name] ++ restInstructions, finalEnv)
    where (restInstructions, finalEnv) = generateOutputs (pc + 3, sp - 1, global, [rest])
generateOutputs env@(pc, sp, global, ((name, addr, Param _ _     _) : rest) : []) = generateOutputs (pc, sp - 1, global, [rest])

generateInputs :: [IMLVal] -> Enviroment -> ([Instruction], Enviroment)
generateInputs statements startEnv = foldl connectInput ([], addLocalScope [] startEnv) statements

-- TODO better name
connectInput :: ([Instruction], Enviroment) -> IMLVal -> ([Instruction], Enviroment)
connectInput (instructions, env) statement = (instructions ++ newInstructions, newEnv)
    where (newInstructions, newEnv) = generateInput statement env

generateInput :: IMLVal -> Enviroment -> ([Instruction], Enviroment)
generateInput p@(ParamDeclaration flowMode changeMode (Ident name) imlType) env@(pc, sp, global, locals) = (newInstructions, newEnv)
    where newInstructions = generateInputCode p
          newIdent = (name, sp, Param imlType flowMode changeMode)
          newEnv = (pc + length newInstructions, sp + 1, global, addToLocalScope locals newIdent)

generateInputCode :: IMLVal -> [Instruction]
generateInputCode (ParamDeclaration Out  _ (Ident name) _) = [ loadIm32 0 ]
generateInputCode (ParamDeclaration _    _ (Ident name) _) = [ input32 name ]

generateFunctions :: [IMLVal] -> Enviroment ->  ([Instruction], Enviroment)
generateFunctions [] env = ([], env)
generateFunctions statements startEnv = (instructions, newEnv)
    where (instructions, newEnv) = foldl connectFunction ([], startEnv) statements

connectFunction :: ([Instruction], Enviroment) -> IMLVal -> ([Instruction], Enviroment)
connectFunction (instructions, env@(pc, _, _, _)) statement@(FunctionDeclaration (Ident name) _ _) = (instructions ++ newInstructions, newEnv)
    where (newInstructions, functionEnv, inputScope) = generateFunction statement env
          newIdent = (name, pc, Function inputScope)
          -- add the function to the global scope and remove the last local scope (which is from the function)
          newEnv = addToGlobalScope functionEnv newIdent 

generateFunction :: IMLVal -> Enviroment -> ([Instruction], Enviroment, Scope)
generateFunction (FunctionDeclaration name params statements) env = (instructions, removeLocalScope newEnv, (head . getLocalScopes) inputEndEnv)
    where (paramInstructions, inputEndEnv) = generateFunctionInputs (reverse params) (addLocalScope [] env)
          (statementInstructions, functionEndEnv) = generateMultiCode statements inputEndEnv 
          (returnInstruction, returnEndEnv) = ([ Return 0 ], updatePc functionEndEnv 1)
          instructions = paramInstructions ++ statementInstructions ++ returnInstruction
          newEnv = returnEndEnv
    
generateFunctionInputs :: [IMLVal] -> Enviroment -> ([Instruction], Enviroment)
generateFunctionInputs statements startEnv = foldl connectFunctionInput ([], startEnv) statements

connectFunctionInput :: ([Instruction], Enviroment) -> IMLVal -> ([Instruction], Enviroment)
connectFunctionInput (instructions, env) statement = (instructions ++ newInstructions, newEnv)
    where (newInstructions, newEnv) = generateFunctionInput statement env

generateFunctionInput :: IMLVal -> Enviroment -> ([Instruction], Enviroment)
generateFunctionInput p@(ParamDeclaration flowMode changeMode (Ident name) imlType) env@(pc, sp, global, locals) = (newInstructions, newEnv)
    where newInstructions = generateFunctionInputCode p
          newIdent = (name, - (1 + length ((head . getLocalScopes) env)), Param imlType flowMode changeMode)
          newEnv = (pc + length newInstructions, sp, global, addToLocalScope locals newIdent)

generateFunctionInputCode :: IMLVal -> [Instruction]
generateFunctionInputCode (ParamDeclaration flowMode _ (Ident name) _) = [ ]

-- HERE THE LOCAL ENVIROMENT GETS UPDATED
generateScopeCode ::  [IMLVal] -> Enviroment -> ([Instruction], Enviroment)
generateScopeCode statements startEnv = dropLocalScope $ generateMultiCode statements (addLocalScope [] startEnv)
    where dropLocalScope (instructions, (pc, sp, global, _ : locals)) = (instructions, (pc, sp, global, locals))
generateMultiCode :: [IMLVal] -> Enviroment -> ([Instruction], Enviroment)
generateMultiCode instructions startEnv = foldl connectCode ([], startEnv) instructions

connectCode :: ([Instruction], Enviroment) -> IMLVal -> ([Instruction], Enviroment)
connectCode (instructions, env) statement = (instructions ++ newInstructions, newEnv)
    where (newInstructions, newEnv) = generateCode statement env

generateCode :: IMLVal -> Enviroment -> ([Instruction], Enviroment)
generateCode (Ident name) env = ([loadAddrRel $ getIdentAddress env name, deref ], updatePcSp 2 1)
generateCode (IdentArray (Ident name) i) env = ([loadAddress arrayAddres, deref ], updatePcSp 2 1)
    where startAddress =  getIdentAddress env name
          ident@(_, add, identInfo) = getIdent env name
          imlType = extractImlType identInfo
          amax = extractArrayMax imlType
          amin = extractArrayMin imlType
          arrayAddres = getArrayAddress i amin amax startAddress
generateCode (Literal (IMLInt i)) env = ([loadIm32 $ toInteger i], updatePcSp 1 1)
generateCode (MonadicOpr Parser.Minus expression) env = (expressionInstructions ++ [neg], updatePc newEnv 1)
    where (expressionInstructions, newEnv) = generateCode expression env
generateCode (Assignment imlIdent@(Ident name) expression) env = generateAssignmentCode imlIdent (thd3 $ getIdent env name) (generateCode expression env)
generateCode (Assignment imlIdent@(IdentArray (Ident name) _) expression) env = generateAssignmentCode imlIdent (thd3 $ getIdent env name) (generateCode expression env)
generateCode (IdentFactor ident Nothing) env = generateCode ident env
generateCode (DyadicOpr op a b) env = (expressionInstructions ++ [getDyadicOpr op], updatePcSp 1 -1)
    where (expressionInstructions, newEnv) = (fst (generateCode a env) ++ fst (generateCode b env), snd $ generateCode b (snd $ generateCode a env))
generateCode (If condition ifStatements elseStatements) env@(_, _, global, locals) = (conditionInstructions ++ [condJump (getPc ifEndEnv + 1)] ++ ifStatementInstructions ++ [uncondJump (getPc elseEndEnv + 1)] ++ elseStatementInstructions, elseEndEnv)
    where (conditionInstructions, condEndEnv) = generateCode condition env
          (ifStatementInstructions, ifEndEnv) = generateScopeCode ifStatements (updatePc condEndEnv 1) --TODO use the hole elseStament
          (elseStatementInstructions, elseEndEnv) = generateScopeCode elseStatements (updatePc ifEndEnv 1) --TODO use the hole elseStament
generateCode (FunctionCall (Ident name) params) env = (prepParams ++ [ call $ getIdentAddress env name ] ++ storeOutputs, storeOutputsEndEnv)
    where (prepParams, prepParamsEndEnv) = generateMultiCode params env
          (storeOutputs, storeOutputsEndEnv) = generateStoreOutputsCode (zip params (getParams $ getIdentInfo env name)) (updatePc prepParamsEndEnv 1)
generateCode (While condition statements) env@(_, _, global, locals) =  (conditionInstructions ++ [condJump (getPc statemEndEnv + 1)] ++ statmentInstructions ++ [uncondJump (getPc env)], statemEndEnv)
    where (conditionInstructions, condEndEnv) = generateCode condition env
          (statmentInstructions, statemEndEnv) = generateScopeCode statements (updatePc condEndEnv 2)
generateCode (IdentDeclaration changeMode (Ident name) imlType) env = generateIdentDeclarationCode name changeMode imlType env
generateCode s _ = error $ "not implemented" ++ show s

generateStoreOutputsCode :: [(IMLVal, Ident)] -> Enviroment -> ([Instruction], Enviroment)
generateStoreOutputsCode [] env = ([], env)
generateStoreOutputsCode (next : rest) env = (newInstructions ++ restInstructions, finalEnv)
    where (newInstructions, newEnv) = handleNext next env
          (restInstructions, finalEnv) = generateStoreOutputsCode rest newEnv

handleNext :: (IMLVal, Ident) -> Enviroment -> ([Instruction], Enviroment)
handleNext (IdentFactor (Ident name) _, (_, _, Param _ Out   changeMode)) env@(_, sp, _, _) = ([ loadAddrRel $ getIdentAddress env name, loadAddrRel $ sp - 1, deref, store ], updateSp (updatePc env 4) (-1))
handleNext (IdentFactor (Ident name) _, (_, _, Param _ InOut changeMode)) env@(_, sp, _, _) = ([ loadAddrRel $ getIdentAddress env name, loadAddrRel $ sp - 1, deref, store ], updateSp (updatePc env 4) (-1))
handleNext _ env = ([], updateSp env (-1))

generateIdentDeclarationCode :: String -> IMLChangeMode -> IMLType -> Enviroment -> ([Instruction], Enviroment)
generateIdentDeclarationCode name changeMode Int env = ([loadIm32 0], updatePcSp 1 1)
    where newEnv = addLocalIdent env (name, getSp env, CodeGenerator.Var Int changeMode)
generateIdentDeclarationCode name changeMode var@(ClampInt cmin cmax) env 
    | cmax <= cmin = error "Max of Clamp must be greater than min"
    | otherwise = ([loadIm32 $ toInteger cmin], updatePcSp newEnv 1 1)
    where newEnv = addLocalIdent env (name, getSp env, CodeGenerator.Var var changeMode)
generateIdentDeclarationCode name changeMode var@(ArrayInt amin amax) env
    | amax <= amin = error "Max of Array must be greater than min"
    | otherwise = (instructions, updatePcSp newEnv (amax - amin) (amax - amin))
    where instructions = generateIdentDeclarationArrayCode amin amax
          newEnv = addLocalIdent env (name, getSp env, CodeGenerator.Var var changeMode)

generateIdentDeclarationArrayCode :: Int -> Int -> [Instruction]
generateIdentDeclarationArrayCode i amax
    | i > amax = []
    | otherwise = [loadIm32 0] ++ generateIdentDeclarationArrayCode (i+1) amax

generateAssignmentCode :: IMLVal -> IdentInfo -> ([Instruction], Enviroment) -> ([Instruction], Enviroment)
generateAssignmentCode (Ident name) (CodeGenerator.Var var@(ClampInt _ _) _) (exprInst, exprEnv) = ([loadInst] ++ exprInst ++ clampInst, updatePc clampEnv 1)
    where loadInst = loadAddress $ getIdentAddress exprEnv name
          (clampInst, clampEnv) = generateClampAssignmentCode loadInst var exprEnv
generateAssignmentCode (Ident name) (Param var@(ClampInt _ _) _ _) (exprInst, exprEnv) = ([loadInst] ++ exprInst ++ clampInst, updatePc clampEnv 1)
    where loadInst = loadAddress $ getIdentAddress exprEnv name
          (clampInst, clampEnv) = generateClampAssignmentCode loadInst var exprEnv
generateAssignmentCode (IdentArray (Ident name) i) (CodeGenerator.Var var@(ArrayInt amin amax) _) (exprInst, exprEnv) = ([loadAddress arrayAddres] ++ exprInst ++ [store], updatePc exprEnv 2)
    where startAddress = getIdentAddress exprEnv name
          arrayAddres = getArrayAddress i amin amax startAddress
generateAssignmentCode (Ident name) _ (exprInst, exprEnv)= ([loadAddrRel $ getIdentAddress exprEnv name] ++ exprInst ++ [store], updatePc exprEnv 2)

-- preconditon address is already loaded in the stack
generateClampAssignmentCode :: Instruction -> IMLType -> Enviroment -> ([Instruction], Enviroment)
generateClampAssignmentCode loadAddInst (ClampInt cmin cmax) env = (checkMaxInst ++ checkMinInst ++ storeInRangeInst ++ storeOverMax ++ storeUnderMin, updatePc env (checkMaxLength + checkMinLength + storeInRangeLength + storeUnderMinLenght + storeOverMaxLenght))
    where startPc = getPc env
          checkMaxLength = 4
          checkMinLength = 4
          storeInRangeLength = 2
          storeOverMaxLenght = 5
          storeUnderMinLenght = 4
          afterAssignmentPc = startPc + checkMaxLength + checkMinLength + storeInRangeLength + storeUnderMinLenght + storeOverMaxLenght + 1
          checkMaxInst = [Dup, loadIm32 $ toInteger cmax, le32, condJump (startPc + checkMaxLength + checkMinLength + storeInRangeLength + 1)]
          checkMinInst = [Dup, loadIm32 $ toInteger cmin, ge32, condJump (startPc + checkMaxLength + checkMinLength + storeInRangeLength + storeOverMaxLenght + 1)]
          storeInRangeInst = [Store, uncondJump afterAssignmentPc]
          storeOverMax = [Store, loadAddInst, loadIm32 $ toInteger cmax, store, uncondJump afterAssignmentPc]
          storeUnderMin = [Store, loadAddInst, loadIm32 $ toInteger cmin, store]
generateClampAssignmentCode _ _ _ = error "Type is not a ClampInt"

-- generateCodeWithNewScope :: [IMLVal] -> Enviroment -> ([Instruction], Enviroment)
-- generateCodeWithNewScope vals env = generateStatmensCode vals (addNewLocalScope env) []

-- generateStatmensCode :: [IMLVal] -> Enviroment -> [Instruction] -> ([Instruction], Enviroment)
-- generateStatmensCode [] env intructions = (intructions, removeLocalScope env)
-- generateStatmensCode (val:rest) env intructions = generateStatmensCode rest newEnv (intructions ++ newInstructions)
--     where (newInstructions, newEnv) = generateCode val env

getDyadicOpr :: IMLOperation -> Instruction
getDyadicOpr Parser.Plus = add32
getDyadicOpr Parser.Minus = sub32
getDyadicOpr Parser.Times = mult32
getDyadicOpr Parser.Div = divFloor32
getDyadicOpr Parser.Lt = lt32
getDyadicOpr Parser.Ge = ge32
getDyadicOpr Parser.Eq = eq32
getDyadicOpr Parser.Ne = ne32
getDyadicOpr Parser.Gt = gt32
getDyadicOpr Parser.Le = le32
getDyadicOpr Parser.And = error "TODO"
getDyadicOpr Parser.Or = error "TODO"
getDyadicOpr Parser.Not = error "TODO"

extractArrayMin :: IMLType -> Int
extractArrayMin (ArrayInt amin _) = amin

extractArrayMax :: IMLType -> Int
extractArrayMax (ArrayInt _ amax) = amax

getArrayAddress :: Int -> Int -> Int -> Int -> Int
getArrayAddress i amin amax startAddr
    | i < amin = error ("index: " ++ show i ++ " of array is to small must be at least " ++ show amin)
    | i > amax = error "index of array is to large"
    | otherwise = startAddr + (i - amin)

program :: (Array Int Instruction)
-- program = array (0, 4) [(0, LoadIm Int32VmTy (Int32VmVal (fromRight $ fromIntegerToInt32 5))), (1, LoadIm Int32VmTy (Int32VmVal (fromRight $ fromIntegerToInt32 4))), (2, Add Int32VmTy mempty), (3, Output (IntTy (32 :: Int)) "HALLO"), (4, Stop)]
program = array (0, 4) [(0, Input (IntTy 32) (rc2loc (1,1)) "Test"), (1, LoadIm Int32VmTy (Int32VmVal (fromRight $ fromIntegerToInt32 5))), (2, Add Int32VmTy mempty), (3, Output (IntTy (32 :: Int)) "HALLO"), (4, Stop)]