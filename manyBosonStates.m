(* ::Package:: *)

(* Abort for old, unsupported versions of Mathematica *)
If[$VersionNumber < 10,
  Print["manyBosonStates requires Mathematica 10.0 or later."];
  Abort[]
];

x_\[CirclePlus]y_ := Mod[x + y, 2];


BeginPackage["manyBosonStates`"];

Unprotect @@ Names["manyBosonStates`*"];
ClearAll @@ Names["manyBosonStates`*"];

mol::usage = "mol[{list}] represents a quantum many-body state expressed as a Mode Occupation List, with the i-th element of list representing the number of bosons in the i-th mode.";
mal::usage = "mal[{list},m] represents a quantum many-body state expressed as a Mode Assignment List, with the i-th element of list representing the mode occupied by the i-th photons, and with m being the total number of modes available to each boson.";
bm::usage = "bm[matrix] represents a quantum many-body state expressed as a Binary Matrix, with the i-th row of matrix being the binary representation of the i-th element of the corresponding MAL representation.";
nOfPhotons::usage = "nOfPhotons[manyBodyState] returns the number of photons in the state.";
nOfModes::usage = "nOfModes[manyBodyState] returns the number of modes over which the state is defined.";
toMOL::usage = "The output of toMOL[stuff] is always a List enclosed in a mol Head.
toMOL[list] assumes that the input is in MOL form, and returns it wrapped in the mol Head.
toMOL[mol] does nothing but returning its input.
toMOL[list,n] assumes that list and n describe a quantum state in MAL form, and proceeds with the conversion.
toMOL[mal] converts the quantum state from MAL to MOL form.
toMOL[bm] converts the quantum state from binaryMatrix to MOL form.";
toMAL::usage = "toMAL[state] returns state expressed as a Mode Assignment List, wrapped in the Head mal.
The general form of this output will thus be mal[listOfModes,numberOfModes].";
toBM::usage = "toBM[state] returns state in BinaryMatrix form, wrapped in the Head bm.";
toSameForm::usage = "toSameForm[modelState,stateToFormat] returns stateToFormat converted in the same form of modelState.";

manyBodyStateQ::usage = "manyBosonStateQ[state] returns True if state is a recognized many-body state.";

listCFMOLs::usage = "listCFMOLs[m,n] returns the set of collision-free many-body states of n bosons in m modes as Mode Occupation Lists.";
listMOLs::usage = "listMOLs[m,n] returns the set of many-body states of n bosons in m modes as Mode Occupation Lists.";
randomCFMOL::usage = "randomCFMOL[m,n] returns a randomly chosen collision-free many-body state of n bosons in m modes, as a Mode Occupation List.";

scatteringAmplitude::usage = "scatteringAmplitude[inputState,outputState,unitaryMatrix] computes the probability amplitude of the many-body state inputState to evolve into outputState when the evolution is described by unitaryMatrix.";
scatteringAmplitudeNoMem::usage = "scatteringAmplitudeNoMem[input,output,matrix] is equal to scatteringAmplitude, but does not memoize the results.";
scatteringProbability::usage = "scatteringProbability[inputState,outputState,unitaryMatrix] gives the squared modulus of the corresponding scatteringAmplitude.";
evolveManyBodyState::usage = "evolveManyBodyState[inputState,unitaryEvolution] gives the set of all possible output many-body states resulting from the evolution of inputState through unitaryEvolution.
The output is an association with the structure <| outputMOL->scatteringAmplitude, ... |>.";

suppressedQ::usage = "suppressedQ[inputState,outputState,unitaryEvolution] returns False and True respectively in the evolution of inputState through unitaryEvolution can or cannot result in outputState.";
suppressedOutputsCount::usage = "suppressedOutputsCount[m,n,unitaryMatrix] gives the number of suppressed output states for each injected input state.
suppressedOutputsCount[inputState,unitaryMatrix] gives the number of suppressed output states when the input is inputState.";
suppressedOutputsList::usage = "suppressedOutputsList[inputState,unitaryEvolution] gives the list of output many-body states which are suppressed when evolving inputState through unitaryEvolution.";
scattershotSamplingSuppressionRate::usage = "scattershotSamplingSuppressionRate[m,n,matrix] gives an approximated estimate of the fraction of suppressed input/output pairs of the matrix given in input.";
manyBosonMatrix::usage = "manyBosonMatrix[matrix,n] returns the matrix induced in n-boson Fock space from the input given matrix.
manyBosonMatrix[unitaryFunction,m,n] works like the above syntax, except that unitaryFunction is a function which takes as input the number of modes m and produces the corresponding m-dimensional matrix.
Available options:
  outputStates -> (\"collisionFree\" | \"nonCollisionFree\" | \"all\"), specifies which input/output combinations to output;
  monitor -> (True | False), specifies whether to print a progress bar monitoring the progress.";
niceForm::usage = "niceForm[matrix] returns a formatted and coloured version of the input given matrix, for display purpuses.";


mal::wrongNumberOfModes = "The number of modes is incompatible with the given list of modes.";
mol::wrongFormat = "A Mode Occupation List is a List of non negative integer numbers.";
mal::wrongFormat = "A Mode Assignment List is either a List of positive numbers or a List of positive numbers together with a single positive nunber specifying the number of modes.";
bm::wrongFormat = "A Binary Matrix is a 2 dimensional matrix of 0s and 1s.";


Begin["`Private`"];


(*If[Length@Position[$Path,#]\[Equal]0,AppendTo[$Path,#]]&@"C:\\Users\\lk\\Documents\\docs\\coding\\mathematica";*)
Needs["utilities`"];
Needs["PermanentCode`"];

(* For compatibility purposes, add a simple implementation of AssociationMap if not already defined (for versions < 10.0) *)
If[!NameQ["AssociationMap"],
  AssociationMap[f_, list_] := Association[(# -> f[#])& /@ list];
]


modeOccupationListQ[allegedMOL___] := MatchQ[mol@allegedMOL, mol@{__Integer?NonNegative}];
modeAssignmentListQ[allegedMAL___] := MatchQ[allegedMAL, mal[{__Integer?Positive}, _Integer?Positive]];
binaryMatrixQ[allegedBM___] := MatchQ[bm@allegedBM, bm@{{__Integer?(# == 0 || # == 1&)}..}];
manyBodyStateQ[allegedState_] := modeOccupationListQ@allegedState || modeAssignmentListQ@allegedState || binaryMatrixQ@allegedState;


bm /: MatrixForm[bm[l_List]] := MatrixForm[l];
bm /: bm[bm[l_]] := bm[l];
mol /: mol[mol[l_]] := mol[l];
mal /: mal[mal[l_]] := mal[l];

(*
mal[mol : {__Integer?Positive}] := mal[mol,
  FromDigits[IntegerDigits[Max @ mol - 1, 2] /. 0 -> 1, 2] + 1
];

mal[args___] /; !MatchQ[{args},
  {{__Integer ? Positive}, _Integer ? Positive} | {{_Integer ? Positive}}
] := Message[mal::wrongFormat];

mal[listOfModes_List, numberOfModes_Integer] /; (
  Max @ listOfModes > numberOfModes
) := Message[mal::wrongNumberOfModes];

mol[Except[{__Integer?NonNegative}]] := Message[mol::wrongFormat];

bm[Except @ {{__Integer ? (# == 0 || # == 1)&}..}] := Message[bm::wrongFormat];
*)

Attributes[mol] = {Protected};
Attributes[mal] = {Protected};
Attributes[bm] = {Protected};


nOfPhotons[mol[occupationNumbers_]] := Total @ occupationNumbers;
nOfPhotons[occupationNumbers : {__Integer}] := nOfPhotons@mol@occupationNumbers;
nOfPhotons[mal[listOfModes_, _]] := Length@listOfModes;
nOfPhotons[bm[matrix_]] := Length@matrix;
nOfPhotons[matrix : {{__Integer?(# == 0 || # == 1&)}..}] := nOfPhotons@bm@matrix;


nOfModes[mol[occupationNumbers_]] := Length@occupationNumbers;
nOfModes[occupationNumbers : {__Integer}] := nOfModes@mol@occupationNumbers;
nOfModes[mal[_, numberOfModes_]] := numberOfModes;
nOfModes[bm[matrix_]] := Log[2, Length@Transpose@matrix];
nOfModes[matrix : {{__Integer?(# == 0 || # == 1&)}..}] := nOfModes@bm@matrix;


convertMOLtoMAL[mol_List] := Do[
  If[
    mol[[i]] > 0,
    Do[Sow@i, {mol[[i]]}]
  ], {i, Length@mol}] // Reap // Last // Last
convertMOLtoMAL[inputState_mol] := mal[convertMOLtoMAL[First@inputState], Length@First@inputState]

convertMALtoMOL[mal_List, numberOfModes_Integer] := Block[{mol = ConstantArray[0, numberOfModes]},
  Do[mol[[i]]++, {i, mal}];mol
];
convertMALtoMOL[inputState_mal] := Which[
  Length@inputState == 1, convertMALtoMOL[First@inputState, Max@First@inputState],
  Length@inputState == 2, convertMALtoMOL[First@inputState, Last@inputState]
];
convertMALtoBM[inputMAL : {__Integer}, m_Integer?(IntegerQ@Log[2, #]&)] := IntegerDigits[#, 2, Log[2, m]]& /@ (inputMAL - 1);
convertMALtoBM[inputMAL_mal] := Which[
  Length@inputMAL == 2, convertMALtoBM[First@inputMAL, Last@inputMAL],
  Length@inputMAL == 1, convertMALtoBM[First@inputMAL, Max@inputMAL]
];

(*convertMOLtoBM[inputMOL : {__Integer}] := PadLeft[IntegerDigits[# - 1, 2], Log[2, Length@inputMOL]]& /@ Flatten@Position[inputMOL, 1];*)
convertMOLtoBM[inputMOL : {__Integer}] := convertMALtoBM[convertMOLtoMAL[inputMOL], Length @ inputMOL];
(*convertMOLtoBM[inputMOL_mol]:=convertMOLtoBM[First@inputMOL]*)

convertBMtoMAL[inputBinaryMatrix : {{__Integer}..}] := 1 + FromDigits[#, 2]& /@ inputBinaryMatrix // Sort
(*convertBMtoMAL[inputBM_bm]:=convertBMtoMAL[First@inputBM]*)
convertBMtoMOL[inputBinaryMatrix : {{__Integer}..}] := convertMALtoMOL[convertBMtoMAL@inputBinaryMatrix, 2^Length@Transpose@inputBinaryMatrix]
(*convertBMtoMOL[inputBM_bm]:=convertBMtoMOL[First@inputBM]*)


toMAL::wrongHead = "The allowed Heads are List, mol, mal, bm.";
toBM::wrongHead = "The allowed Heads are List, mol, mal, bm.";
toMOL::wrongHead = "The allowed Heads are List, mol, mal, bm.";

toMOL[inputState : {__Integer}] := mol@inputState;
toMOL[inputState : {{__Integer?(# == 0 || # == 1&)}..}] := mol@convertBMtoMOL@inputState;
toMOL[inputState_mol] := inputState;
toMOL[inputState : {__Integer}, numberOfModes_Integer] := mol@convertMALtoMOL[inputState, numberOfModes];
toMOL[inputState_mal] := convertMALtoMOL[inputState] // mol;
toMOL[inputState_bm] := convertBMtoMOL[inputState] // mol;
toMOL[_] := Message[toMOL::wrongHead];

toMAL[inputState : {__Integer}] := mal[convertMOLtoMAL@inputState, Length@inputState];
toMAL[inputState : {{__Integer?(# == 0 || # == 1&)}..}] := toMAL[bm@inputState];
toMAL[inputState_mol] := toMAL[First@inputState];
toMAL[inputState_mal] := inputState;
toMAL[inputState_bm] := mal[convertBMtoMAL[inputState], 2^Length@Transpose@First@inputState];
toMAL[_] := Message[toMAL::wrongHead];

toBM[inputState : {__Integer}] := bm@convertMOLtoBM@inputState;
toBM[inputState : {{__Integer?(# == 0 || # == 1&)}..}] := toBM[bm@inputState];
toBM[inputState_mol] := toBM[First@inputState];
toBM[inputState_mal] := bm@convertMALtoBM@inputState;
toBM[inputState_bm] := inputState;
toBM[_] := Message[toBM::wrongHead];


SyntaxInformation[toSameForm] = {"ArgumentsPatterns" -> {_, _}};
toSameForm[modelState_?manyBodyStateQ, stateToFormat_?manyBodyStateQ] := Which[
  modeOccupationListQ @ modelState,
  If[Head @ modelState === mol,
    toMOL @ stateToFormat,
    First @ toMOL @ stateToFormat
  ],
  modeAssignmentListQ @ modelState, toMAL @ stateToFormat,
  binaryMatrixQ @ modelState,
  If[Head @ modelState === bm,
    toBM @ stateToFormat,
    First @ toBM @ stateToFormat
  ]
];


SyntaxInformation[listCFMOLs] = {"ArgumentsPattern" -> {_, _, OptionsPattern[]}};
Options[listCFMOLs] = {sortBy -> "default"};
listCFMOLs[m_Integer, n_Integer, OptionsPattern[]] := Function[output,
  Which[
    StringQ @ OptionValue @ sortBy &&
        ToLowerCase @ OptionValue @ sortBy == "default",
    output,
    (Head[#] === Symbol || Head[#] === Function)& @ OptionValue @ sortBy,
    SortBy[OptionValue @ sortBy] @ output
  ]
] @ Permutations @ PadRight[ConstantArray[1, n], m];


Options[randomCFMOL] = {method -> "default"};
SyntaxInformation[randomCFMOL] = {"ArgumentsPattern" -> {_, _, OptionsPattern[]}};
randomCFMOL[m_Integer, n_Integer, opts : OptionsPattern[]] := Which[
  ToLowerCase@OptionValue@method == "default",
  If[
    m < 32, RandomChoice@listCFMOLs[m, n],
    convertMALtoMOL[
      Last@Last@Reap@Block[{listToPick = Range@m, choice},
        Do[
          choice = Sow@RandomChoice@listToPick;
          listToPick = DeleteCases[listToPick, _?(# == choice&)],
          {n}
        ]
      ],
      m
    ]
  ],
  ToLowerCase@OptionValue@method == "alwaysfromlist",
  RandomChoice@listCFMOLs[m, n],
  ToLowerCase@OptionValue@method == "alwaysrandom",
  convertMALtoMOL[#, m]&[
    Last@Last@Reap@Block[{listToPick = Range@m, choice},
      Do[
        choice = Sow@RandomChoice@listToPick;
        listToPick = DeleteCases[listToPick, _?(# == choice&)],
        {n}
      ]
    ]
  ]
];


ClearAll[listMOLs];
SyntaxInformation[listMOLs] = {"ArgumentsPattern" -> {_, _, OptionsPattern[]}};
Options[listMOLs] = {sortBy -> "default"};
listMOLs[m_Integer, n_Integer, OptionsPattern[]] := Function[out,
  Which[
    StringQ@OptionValue@sortBy && ToLowerCase@OptionValue@sortBy == "default",
    out,
    Head[OptionValue@sortBy] === Symbol || Head[OptionValue@sortBy] === Function,
    SortBy[OptionValue@sortBy]@out
  ]
][
  (Sequence @@ Permutations@PadRight[#, m])& /@ IntegerPartitions[n, m]
]


SyntaxInformation[scatteringAmplitude] = {"ArgumentsPattern" -> {_, _, _}};

scatteringAmplitude[
  inputState_?manyBodyStateQ,
  outputState_?manyBodyStateQ,
  unitaryMatrix_List
] := With[
  {inputMAL = First@toMAL@inputState,
    outputMAL = First@toMAL@outputState,
    inputMOL = First@toMOL@inputState,
    outputMOL = First@toMOL@outputState},
  Permanent[
    Table[
      unitaryMatrix[[inputMAL[[i]], outputMAL[[j]]]],
      {i, Length@inputMAL}, {j, Length@inputMAL}
    ]
  ] / Sqrt[Times @@ Factorial @ inputMOL] / Sqrt[Times @@ Factorial @ outputMOL]
];

scatteringAmplitude[
  inputState_,
  outputState_,
  unitaryMatrix_
] := scatteringAmplitude[inputState, outputState, unitaryMatrix[nOfModes @ inputState]];

(*
scatteringAmplitude[
  inputState_,
  outputState_,
  unitaryMatrix : (_Symbol | _Function)
] := scatteringAmplitude[
  inputState,
  outputState,
  unitaryMatrix
] = scatteringAmplitude[
  inputState,
  outputState,
  unitaryMatrix[nOfModes @ inputState]
];
*)

SyntaxInformation[scatteringAmplitudeNoMem] = {"ArgumentsPattern" -> {_, _, _}};
scatteringAmplitudeNoMem[inputState_, outputState_, unitaryMatrix : (_Symbol | _Function)] := scatteringAmplitude[inputState, outputState, unitaryMatrix[Length@First@toMOL@inputState]]


SyntaxInformation[scatteringProbability] = {"ArgumentsPattern" -> {_, _, _}};
scatteringProbability[inputMOL_, outputMOL_, unitaryMatrix_] := Abs[scatteringAmplitude[inputMOL, outputMOL, unitaryMatrix]]^2

Options[evolveManyBodyState] = {outputStates -> "collisionFree", monitor -> False};
SyntaxInformation[evolveManyBodyState] = {"ArgumentsPattern" -> {_, _, OptionsPattern[]}};
evolveManyBodyState[inputState_?manyBodyStateQ, unitaryMatrix_List, opts : OptionsPattern[]] := With[{inputMOL = First@toMOL@inputState},
  Module[{molsToCheck},
    Which[
      ToLowerCase@OptionValue@outputStates == "collisionfree" || ToLowerCase@OptionValue@outputStates == "cf",
      molsToCheck = listCFMOLs[Length@inputMOL, Total@inputMOL],
      ToLowerCase@OptionValue@outputStates == "all",
      molsToCheck = listMOLs[Length@inputMOL, Total@inputMOL],
      ToLowerCase@OptionValue@outputStates == "noncollisionfree" || ToLowerCase@OptionValue@outputStates == "bunched" || ToLowerCase@OptionValue@outputStates == "ncf",
      molsToCheck = Select[listMOLs[Length@inputMOL, Total@inputMOL], Max@# > 1&]
    ];
    If[!TrueQ@OptionValue@monitor,
    (*KeySort@AssociationMap[scatteringAmplitude[inputMOL,#,unitaryMatrix]&,molsToCheck],*)
      KeySort@Association[
        # -> scatteringAmplitude[inputMOL, #, unitaryMatrix]& /@ molsToCheck
      ],
      Module[{i = 0},
        Monitor[
          Do[
            i++;Sow[<|outputMOL -> scatteringAmplitude[inputMOL, outputMOL, unitaryMatrix]|>],
            {outputMOL, molsToCheck}
          ] // Reap // Last // Last // Association,
          progressBar[i / Length@molsToCheck 100 // N]
        ]
      ]
    ]
  ]
]
evolveManyBodyState[inputState_?manyBodyStateQ, unitaryMatrix : (_Symbol | _Function), opts : OptionsPattern[]] := evolveManyBodyState[inputState, unitaryMatrix[Length@First@toMOL@inputState], opts]


Options[suppressedQ] = {memoize -> True, supprThreshold -> 0};
SyntaxInformation[suppressedQ] = {"ArgumentsPattern", {_, _, _, OptionsPattern[]}};
suppressedQ[
  inputState_?manyBodyStateQ,
  outputState_?manyBodyStateQ,
  unitaryEvolution : (_List | _Symbol | _Function),
  opts : OptionsPattern[]
] := If[OptionValue@supprThreshold == 0,
  If[TrueQ @ OptionValue @ memoize,
    Chop @ N @ scatteringAmplitude[inputState, outputState, unitaryEvolution] == 0,
    Chop @ N @ scatteringAmplitudeNoMem[inputState, outputState, unitaryEvolution] == 0
  ],
(* else, if supprThreshold is not equal to zero (but it should be greater), *)
  If[TrueQ @ OptionValue @ memoize,
    Chop @ Abs @ N @ scatteringAmplitude[inputState, outputState, unitaryEvolution] <= OptionValue@supprThreshold,
    Chop @ Abs @ N @ scatteringAmplitudeNoMem[inputState, outputState, unitaryEvolution] <= OptionValue@supprThreshold
  ]
];


Options[suppressedOutputsCount] = {
  "Method" -> "Exact",
  "NSamples" -> 1000,
  "OutputStates" -> "CollisionFree",
  "Monitor" -> False
};
SyntaxInformation[suppressedOutputsCount] = {
  "ArgumentsPattern", {_, _, _, OptionsPattern[]}
};

suppressedOutputsCount::wrongMethodOpt = "The value of the option \"Method\" \
must be either \"Exact\" or \"Approximated\".";

suppressedOutputsCount[args___, opts : OptionsPattern[]] := Which[
  OptionValue @ "Method" == "Exact",
  suppressedOutputsCountExact[args,
    FilterRules[{opts}, Options @ suppressedOutputsCountExact]
  ],
  OptionValue @ "Method" == "Approximated",
  suppressedOutputsCountApproximated[args,
    FilterRules[{opts}, Options @ suppressedOutputsCountApproximated]
  ],
  True,
  Message[suppressedOutputsCount::wrongMethodOpt];
];


Options[suppressedOutputsCountExact] = {
  "NSamples" -> 1000,
  "OutputStates" -> "CollisionFree",
  "Monitor" -> False
};

suppressedOutputsCountExact[m_Integer, n_Integer,
  unitaryEvolution : (_Symbol | _Function), OptionsPattern[]
] := Module[{outputList},
  (* Prepare list of output states to check *)
  Which[
    Or[
      ToLowerCase @ OptionValue @ "OutputStates" == "collisionfree",
      ToLowerCase @ OptionValue @ "OutputStates" == "cf"
    ],
    outputList = listCFMOLs[m, n],
    ToLowerCase@OptionValue @ "OutputStates" == "all",
    outputList = listMOLs[m, n],
    Or[
      ToLowerCase@OptionValue @ "OutputStates" == "noncollisionfree",
      ToLowerCase@OptionValue@ "OutputStates" == "ncf"
    ],
    outputList = Select[listMOLs[m, n], Max @ # > 1&]
  ];

  Which[
    !TrueQ @ OptionValue @ monitor,
    Association[
      Function[input, input -> Length@Select[outputList, suppressedQ[input, #, unitaryEvolution]&]] /@
          outputList
    ],
    (* MONITORED, EXACT ALGORITHM *)
    TrueQ @ OptionValue @ monitor,
    Module[{i = 0, startingTime = AbsoluteTime[]},
      Monitor[
        AssociationMap[
          Function[input, i++;Length@Select[outputList, suppressedQ[input, #, unitaryEvolution]&]],
          outputList
        ],
        Column[{
          progressBar[i / Binomial[m, n] * 100 // N],
          Row[{"Started at:", DateString[startingTime, {"Hour", ":", "Minute", ":", "Second"}]}, " "],
          Row[{"Time of completion:", DateString[startingTime + # / i * Binomial[m, n](*,{"Hour",":","Minute",":","Second"}*)]}, " "],
          Row[{"Seconds required:", # / i * (Binomial[m, n] - i)}, " "]
        }]& @ (AbsoluteTime[] - startingTime)
      ]
    ]
  ]
];

suppressedOutputsCountExact[inputState_?manyBodyStateQ,
  unitaryMatrix : (_Symbol | _Function),
  opts : OptionsPattern[]
] := Length @ Select[
  evolveManyBodyState[inputState,
    unitaryMatrix,
    Sequence @@ FilterRules[{opts}, Options @ evolveManyBodyState]
  ],
  Chop @ N @ # == 0 &
];

suppressedOutputsCountExact[inputState_,
  unitaryMatrix : {{__?NumericQ}..},
  opts : OptionsPattern[]
] := suppressedOutputsCountExact[inputState, unitaryMatrix&, opts];
(*suppressedOutputsCount[inputMOL_mol,unitaryMatrix:(_Symbol|_Function),opts:OptionsPattern[]]:=suppressedOutputsCount[First@inputMOL,unitaryMatrix,opts]
suppressedOutputsCount[inputMAL_mal,unitaryMatrix:(_Symbol|_Function),opts:OptionsPattern[]]:=suppressedOutputsCount[toMOL@inputMAL,unitaryMatrix,opts]
suppressedOutputsCount[inputBM_bm,unitaryMatrix:(_Symbol|_Function),opts:OptionsPattern[]]:=suppressedOutputsCount[toMOL@inputBM,unitaryMatrix,opts]*)


Options @ suppressedOutputsCountApproximated = {"NSamples" -> 1000};

suppressedOutputsCountApproximated[inputState_?manyBodyStateQ,
  unitaryEvolution : (_Symbol | _Function),
  OptionsPattern[]
] := Module[{counter = 0},
  Do[
    If[suppressedQ[
        inputState,
        randomCFMOL[nOfModes @ #, nOfPhotons @ #] & @ inputState,
        unitaryEvolution
      ],
      counter++
    ],
    {OptionValue @ "NSamples"}
  ];
  counter / OptionValue @ "NSamples"
];

suppressedOutputsCountApproximated[m_Integer, n_Integer,
  unitaryEvolution : (_Symbol | _Function),
  opts : OptionsPattern[]
] := AssociationMap[
  suppressedOutputsCountApproximated[#, unitaryEvolution, opts] &,
  listCFMOLs[m, n]
];

suppressedOutputsCountApproximated::wrongInputs = "The input must match one of \
the two following patterns:
    suppressedOutputsCountApproximated[m, n, unitary]
    suppressedOutputsCountApproximated[input, unitary]."
suppressedOutputsCountApproximated[___] := Message @
  suppressedOutputsCountApproximated::wrongInputs;


Options[suppressedOutputsList] = {outputStates -> "collisionFree"};
SyntaxInformation[suppressedOutputsList] = {"ArgumentsPattern", {_, _, OptionsPattern[]}};
suppressedOutputsList[inputState_?manyBodyStateQ, unitaryEvolution : (_Symbol | _Function), opts : OptionsPattern[]] := Keys@Select[
  evolveManyBodyState[inputState, unitaryEvolution, opts],
  Chop@N@# == 0&
]


Options[scattershotSamplingSuppressionRate] = {nSamples -> 1000, monitorComputation -> False, memoize -> True, supprThreshold -> 0, method -> "approximated"};
SyntaxInformation[scattershotSamplingSuppressionRate] = {"ArgumentsPattern" -> {_, _, _, OptionsPattern[]}};
scattershotSamplingSuppressionRate[m_Integer, n_Integer, unitaryEvolution : (_Symbol | _Function | _List), opts : OptionsPattern[]] := Which[
  ToLowerCase@OptionValue@method == "approximated",
  Module[{counter = 0, iterationIndex = 0},
    Function[code,
      If[TrueQ@OptionValue@monitorComputation,
        Monitor[code, progressBar[100iterationIndex / OptionValue@nSamples // N]],
        code
      ], HoldAll
    ]@Do[
      If[
        suppressedQ[randomCFMOL[m, n, method -> "alwaysRandom"], randomCFMOL[m, n, method -> "alwaysRandom"], unitaryEvolution, FilterRules[{opts}, Options[suppressedQ]]],
        counter++
      ],
      {iterationIndex, OptionValue@nSamples}
    ];counter / OptionValue@nSamples * 100 // N
  ],
  ToLowerCase@OptionValue@method == "exact",
  100 2 Length[Select[
    Subsets[listCFMOLs[m, n], {2}],
    suppressedQ[#[[1]], #[[2]], unitaryEvolution, FilterRules[{opts}, Options[suppressedQ]]]&
  ]] / Binomial[m, n]^2
];


Options[manyBosonMatrix] = {outputStates -> "all", sortBy -> "default", monitor -> False};
SyntaxInformation[manyBosonMatrix] = {"ArgumentsPattern" -> {_, _, OptionsPattern[]}};
manyBosonMatrix[unitaryMatrix_List, n_Integer, OptionsPattern[]] := Module[{mols, localProgressIndex = 0},
  Which[
    n == 1, Return[unitaryMatrix],
    ToLowerCase@OptionValue@outputStates == "all",
    mols = listMOLs[Length@unitaryMatrix, n, sortBy -> OptionValue@sortBy],
    ToLowerCase@OptionValue@outputStates == "collisionfree" || ToLowerCase@OptionValue@outputStates == "cf",
    mols = listCFMOLs[Length@unitaryMatrix, n, sortBy -> OptionValue@sortBy],
    ToLowerCase@OptionValue@outputStates == "noncollisionfree" || ToLowerCase@OptionValue@outputStates == "ncf",
    mols = Select[listMOLs[Length@unitaryMatrix, n, sortBy -> OptionValue@sortBy], Max@# > 1&]
  ];
  (* If the option *monitor* is True, than a local progress bar to monitor the computation is displayed *)
  Function[code,
    If[TrueQ@OptionValue@monitor,
      Monitor[code,
        progressBar[localProgressIndex / Length[mols]^2 * 100 // N]
      ],
      code
    ], HoldAll][
      Table[
        localProgressIndex++;
        scatteringAmplitude[inputMOL, outputMOL, unitaryMatrix],
        {inputMOL, mols}, {outputMOL, mols}
      ]
    ]
];

manyBosonMatrix[unitaryFunction : (_Function | _Symbol), m_Integer, n_Integer, opts : OptionsPattern[]] := manyBosonMatrix[unitaryFunction[m], n, opts]


SyntaxInformation[niceForm] = {"ArgumentsPattern" -> {_}};
niceForm[matrix : {{__?NumericQ}..}] := MatrixForm[matrix] /. {elem_?Positive :> Item[elem, Background -> Green], elem_?Negative :> Item[elem, Background -> Red], elem_Complex :> Item[elem, Background -> Yellow], elem_?(# == 0&) :> Item[elem, Background -> Lighter@Blue]}
niceForm[MatrixForm[matrix_]] := niceForm[matrix]

(* Protect all package symbols *)
With[{syms = Names["manyBosonStates`*"]}, SetAttributes[syms, {Protected, ReadProtected}] ];

End[];
EndPackage[];
