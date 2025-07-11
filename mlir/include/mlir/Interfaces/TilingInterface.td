//===- TilingInterface.td - Interface for tiling operations *- tablegen -*-===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//
//
// This file contains an interface to allow operations to generate a tiled
// implementation of themselves.
//
//===----------------------------------------------------------------------===//

#ifndef MLIR_TILINGINTERFACE
#define MLIR_TILINGINTERFACE

include "mlir/IR/OpBase.td"

def TilingInterface : OpInterface<"TilingInterface"> {
  let description = [{
    This interface allows operations to expose information needed to tile them.

    The intent of this interface is to separate the generation of the loop
    structure (and constructs used for it) from the information needed from
    the operation to be able to tile them. As a result an implementation of
    the tiling algorithm (like `scf::tileUsingSCF`) can generate the inter-tile
    loop structure, and call into the methods of the interface to be able to
    tile any operation that implements the interface.

    This interface is also meant to help with "tile and fuse", i.e. the process
    of fusing a producer with a consumer by
      a) Tiling the consumer
      b) Based on the tile of the producer used by the tiled consumer,
         materialize the tiled implementation of a producer to generate that
         tile (and use it immediately in the consumer)
    You could also fuse a consumer with a producer by
      a) Tiling the producer
      b) Based on the tile produced, materialize the tiled implementation of
         a consumer that uses this tile.
    Note that the tile and fuse does not make any calculation on whether it
    is "profitable to do this", but simply provides a mechansim to implement
    the transformation when such a fusion is needed by the caller.

    For any operation to be tilable, an operation has to implement the
    following two methods (see description below)
      - `getLoopIteratorTypes`
      - `getIterationDomain`
      - `getTiledImplementation`
      - `getResultTilePosition`

    For an operation to be "tiled and fused" with its (already tiled) consumer,
    an operation has to implement the following additional method (see
    description below):
      - `generateResultTileValue`
      - `getIterationDomainTileFromResultTile`

    For an operation to be "tiled and fused" with its (already tiled) producer,
    an operation has to implement the following additional methods (see
    description below):
      - `getTiledImplementationFromOperandTile`
      - `getIterationDomainTileFromOperandTile`.
  }];
  let cppNamespace = "::mlir";
  let methods = [
      InterfaceMethod<
        /*desc=*/[{
          Returns a list of iterator types that describe the number of loops.
        }],
        /*retType=*/"::mlir::SmallVector<::mlir::utils::IteratorType>",
        /*methodName=*/"getLoopIteratorTypes",
        /*args=*/(ins),
        /*methodBody=*/"",
        /*defaultImplementation=*/"return {};"
      >,
      InterfaceMethod<
        /*desc=*/[{
          Returns a list of ranges that describe the loop bounds and
          step for the loops of the operation.
        }],
        /*retTy=*/"::mlir::SmallVector<::mlir::Range>",
        /*methodName=*/"getIterationDomain",
        /*args=*/(ins "::mlir::OpBuilder &":$b),
        /*methodBody=*/"",
        /*defaultImplementation=*/"return {};"
      >,
      InterfaceMethod<
        /*desc=*/[{
          Method to generate the tiled implementation of an operation.

          Given a tile of the iteration space (as returned by
          `getIterationDomain`), generate in-place the code that represents
          the computation corresponding to that tile of the iteration space.
          It is the responsibility of the implementation of this method in
          the operation to generate the slices of the operands needed for the
          tiled implementation.
          - `offsets` provides the offset of the tile in the coordinate system
            of the original iteration space, i.e., if an iteration space
            dimension had non-zero offset, it will be included in the offset
            provided here (as opposed to zero-based offset "relative" to the
            iteration space).
          - `sizes` provides the size of the tile.

          The returned `TilingResult` must return for each result of the
          untiled operation, a `Value` that is the result of the tiled
          operation.
        }],
        /*retType=*/"::mlir::FailureOr<::mlir::TilingResult>",
        /*methodName=*/"getTiledImplementation",
        /*args=*/(ins
            "::mlir::OpBuilder &":$b,
            "::mlir::ArrayRef<::mlir::OpFoldResult> ":$offsets,
            "::mlir::ArrayRef<::mlir::OpFoldResult> ":$sizes),
        /*methodBody=*/"",
        /*defaultImplementation=*/[{
          return {};
        }]
      >,
      InterfaceMethod<
        /*desc=*/[{
          Method to return the position of the result tile computed by the
          tiled operation.

          For operations that return a value (typically a value of type
          `RankedTensorType`), the generated tiled computation has to also
          recompute a replacement for the results of the original operation.
          The tiled implementation of the operation returns a tile of the
          result(s). This methods returns information about what part of the
          result tensor is computed by the tiled implementation. The manner in
          which these tiles get put together to get the final result is upto
          the surrounding loop construct. If an operation has no results, (for
          example an operation that operates only on memrefs), then this method
          need not be implemented by the operation.
          - `resultNumber` is the result number of the original operation
            being processed.
          - `offsets` provides the offset of the tile in the coordinate system
            of the original iteration space, i.e., if an iteration space
            dimension had non-zero offset, it will be included in the offset
            provided here (as opposed to zero-based offset "relative" to the
            iteration space).
          - `sizes` provides the size of the tile.
          - `resultOffsets` is the offsets of the tile of the result generated
            by the tiled implementation (returned by value).
          - `resultSizes` is the size of the tile of the result generated
            by the tiled implementation (returned by value).

          Note: It is undefined behaviour if there is overlap between the
          tiles of the result generated by the tiled implementation.
        }],
        /*retType=*/"::llvm::LogicalResult",
        /*methodName=*/"getResultTilePosition",
        /*args=*/(ins
          "::mlir::OpBuilder &":$b,
          "unsigned":$resultNumber,
          "::mlir::ArrayRef<::mlir::OpFoldResult> ":$offsets,
          "::mlir::ArrayRef<::mlir::OpFoldResult> ":$sizes,
          "::mlir::SmallVector<::mlir::OpFoldResult> &":$resultOffsets,
          "::mlir::SmallVector<::mlir::OpFoldResult> &":$resultSizes),
        /*methodBody=*/"",
        /*defaultImplementation=*/[{
          return failure();
        }]
      >,
      InterfaceMethod<
        /*desc=*/[{
          Method to generate the code that produces a tile of the result.

          This method is required to allow operations to be "tiled and fused"
          with an (already tiled) consumer. Typically, for two operations with
          producer -> consumer relation ship, to compute a tile of the
          consumer a `slice` of the producer is needed. This method allows
          computing that slice of the producer in-place, thereby "fusing"
          the operations at tile-granularity. This method is different from
          `getTiledImplementation`, which produces a tiled implementation
          for a tile of the iteration space. This method produces a tiled
          implementation based on the tile of producer required.
          - `resultNumber` is the result of the producer used by the consumer.
          - `offsets` is the offset of the slice of the producer result used by
            the tiled implementation of the consumer.
          - `sizes` is the size of the slice of the producer result used by the
            consumer.
          If fusion of the producer with the consumer is not legal for the
          operation/result, this method should return failure.

          Note: This method only deals with the mechanism of implementing the
          fusion. In general the fusion might result in recomputation (based on
          the way the result is produced by the producer and the access pattern
          used in the consumer to access). This is upto the caller to handle
          appropriately.
        }],
        /*retType=*/"::mlir::FailureOr<::mlir::TilingResult>",
        /*methodName=*/"generateResultTileValue",
        /*args=*/(ins
          "::mlir::OpBuilder &":$b,
          "unsigned":$resultNumber,
          "::mlir::ArrayRef<::mlir::OpFoldResult>":$offsets,
          "::mlir::ArrayRef<::mlir::OpFoldResult>":$sizes),
        /*methodBody=*/"",
        /*defaultImplementation=*/[{
          return failure();
        }]
      >,
      InterfaceMethod<
        /*desc=*/[{
          Method to generate the tiled implementation of an operation that uses
          exactly a tile of the given operand.

          This method is required to allow operations to be "tiled and fused"
          with an (already tiled) producer. Given a tile of the producer, this
          method generates the tile of the consumer that uses exactly this
          produced tile. In some sense it is the "reverse" of
          `generateResultTileValue`.
          - `operandNumber` is the result of the producer used by the consumer.
          - `offsets` is the offset of the slice of the producer result used by
            the tiled implementation of the consumer.
          - `sizes` is the size of the slice of the producer result used by the
            consumer.
          If it is illegal to fuse with a producer along the given operand for
          an operation, the implementation should return a failure.
        }],
        /*retType=*/"::mlir::FailureOr<::mlir::TilingResult>",
        /*methodName=*/"getTiledImplementationFromOperandTile",
        /*args=*/(ins
          "::mlir::OpBuilder &":$b,
          "unsigned":$operandNumber,
          "::mlir::ArrayRef<::mlir::OpFoldResult>":$offsets,
          "::mlir::ArrayRef<::mlir::OpFoldResult>":$sizes),
        /*methodBody=*/"",
        /*defaultImplementation=*/[{
          return failure();
        }]
      >,
      InterfaceMethod<
        /*desc=*/[{
          Method to return the tile of the iteration domain that uses a given
          tile of the operand.

          This method is required to allow operations to be "tiled and fused"
          with an (already tiled) producer. Given a tile of an operand,
          returns the tile of the iteration space that uses this tile.
          - `operandNumber` is the result of the producer used by the consumer.
          - `offsets` is the offset of the slice of the producer result used by
            the tiled implementation of the consumer.
          - `sizes` is the size of the slice of the producer result used by the
            consumer.
          If it is illegal to fuse with a producer along the given operand for
          an operation, or if this mapping cannot be computed, the
          implementation should return a failure.

          Note that unlike the "tile consumer and fuse producer" case, the
          "tile producer and fuse consumer" requires an additional method to get
          the iteration tile space that encompasses all uses of the given operand
          tile. The reason for this is, consider
          ```mlir
          %1 = scf.for...  {
            %2 = <tiled_producer_op>
            %3 = tensor.insert_slice %2 into ...
            scf.yield %3
          }
          %4 = <consumer_op>)(... %1... )
          ... <some_op>(... %4 ...)
          ```

          when fused this becomes
          ```
          %1 = scf.for...  {
            %2 = <tiled_producer_op>
            %3 = <tiled_consumer_op>(... %2...)
            %4 = tensor.insert_slice %3 into ...
            scf.yield %4
          }
          ... <some_op>(... %1 ...)
          ```

          i.e, when fusing the consumer, the replacement for the result of the
          consumer needs to be returned to replace the uses of the consumer.
          For the tile+fuse algorithm to do this it needs information about
          which tile of the iteration space encompasses all uses of the tile
          produced and use that to compute what are the results produced. Note
          that this iteration space might be the entire iteration space of the
          operation, or multiple operand tiles might map to intersecting
          iteration spaces. It is upto the caller to make sure that it is still
          fusable with producer in this scenario, or it must return a failure.

          Note that this method is only used as a way to implement the
          transformation. It does not provide guarantees on whether such a
          transformation is profitable.

          For most cases `getTiledImplementationFromOperandTile` could be a
          implemented using `getIterationDomainTileFromOperandTile` +
          `getTiledImplementation` methods.
        }],
        /*retType=*/"::llvm::LogicalResult",
        /*methodName=*/"getIterationDomainTileFromOperandTile",
        /*args=*/(ins
          "::mlir::OpBuilder &":$b,
          "unsigned":$operandNumber,
          "::mlir::ArrayRef<::mlir::OpFoldResult> ":$offsets,
          "::mlir::ArrayRef<::mlir::OpFoldResult> ":$sizes,
          "::mlir::SmallVectorImpl<::mlir::OpFoldResult> &":$iterDomainOffsets,
          "::mlir::SmallVectorImpl<::mlir::OpFoldResult> &":$iterDomainSizes),
        /*methodBody=*/"",
        /*defaultImplementation=*/[{
          return failure();
        }]
      >,
      InterfaceMethod<
        /*desc=*/[{
          Method to return the tile of the iteration domain based
          on the given tile of the certain result.

          This method is required to allow operations to be "tiled and fused"
          with an (already tiled) consumer. Given a tile of an result,
          returns the tile of the iteration space that uses this tile.
          - `resultNumber` is the result of the producer used by the consumer.
          - `offsets` is the offset of the slice of the producer result used by
            the tiled implementation of the consumer.
          - `sizes` is the size of the slice of the producer result used by the
            consumer.
          If fusion of the producer with the consumer is not legal for the
          result, or if this mapping cannot be computed, the implementation
          should return a failure.

          For most cases `generateResultTileValue` could be a implemented using
          `getIterationDomainTileFromResultTile` + `getTiledImplementation`
          methods.
        }],
        /*retType=*/"::llvm::LogicalResult",
        /*methodName=*/"getIterationDomainTileFromResultTile",
        /*args=*/(ins
          "::mlir::OpBuilder &":$b,
          "unsigned":$resultNumber,
          "::mlir::ArrayRef<::mlir::OpFoldResult> ":$offsets,
          "::mlir::ArrayRef<::mlir::OpFoldResult> ":$sizes,
          "::mlir::SmallVectorImpl<::mlir::OpFoldResult> &":$iterDomainOffsets,
          "::mlir::SmallVectorImpl<::mlir::OpFoldResult> &":$iterDomainSizes),
        /*methodBody=*/"",
        /*defaultImplementation=*/[{
          return failure();
        }]
      >,
      InterfaceMethod<
        /*desc=*/[{
          Generates the scalar implementation of the operation.

          Given the list `ivs` that represent points in the iteration space
          (as specified by `getIterationDomain()`) returns the scalar operations
          that represent the computation at that point in the iteration space.
          This method is typically used as the "exit path", i.e. once all
          transformations are done, this method can be used to lower to scalar
          code that can then be lowered to LLVM or SPIR-V dialects.
        }],
        /*retType=*/"::llvm::LogicalResult",
        /*methodName=*/"generateScalarImplementation",
        /*args=*/(ins
            "::mlir::OpBuilder &":$b,
            "::mlir::Location ":$loc,
            "::mlir::ValueRange ":$ivs),
        /*methodBody=*/"",
        /*defaultImplementation=*/[{
          return failure();
        }]
      >
  ];
}

def PartialReductionOpInterface :
    OpInterface<"PartialReductionOpInterface", [TilingInterface]> {
  let description = [{
    Interface for allowing operations to expose information needed to
    tile reductions using partial reduction followed by merge. This is
    complementary to TilingInterface to tile reductions.
  }];
  let cppNamespace = "::mlir";
  let methods = [
      InterfaceMethod<
        /*desc=*/[{
          Method to generate a tensor initalized with the identity value of the
          operation reduction. The tensor shape is equal to operation result
          shape with new dimension for each non zero tile size.
        }],
        /*retType=*/"::mlir::FailureOr<SmallVector<Value>>",
        /*methodName=*/"generateInitialTensorForPartialReduction",
        /*args=*/(ins
            "::mlir::OpBuilder &":$b,
            "Location":$loc,
            "::mlir::ArrayRef<::mlir::OpFoldResult>":$sizes,
            "const ::mlir::SetVector<unsigned> &":$reductionDims),
        /*methodBody=*/"",
        /*defaultImplementation=*/[{
          return failure();
        }]
      >,
      InterfaceMethod<
        /*desc=*/[{
          Method to generate a tiled version of the operation where the tiled
          reduction dimension are converted to parallel dimensions with a size
          less or equal to the tile size. This is meant to be used with
          `mergeReductions` method which will combine the partial reductions.
        }],
        /*retType=*/"::mlir::FailureOr<TilingResult>",
        /*methodName=*/"tileToPartialReduction",
        /*args=*/(ins
            "::mlir::OpBuilder &":$b,
            "Location ":$loc,
            "::mlir::ReductionTilingStrategy":$tilingStrategy,
            "ValueRange":$init,
            "::mlir::ArrayRef<::mlir::OpFoldResult>":$offsets,
            "::mlir::ArrayRef<::mlir::OpFoldResult>":$sizes,
            "const ::llvm::SetVector<unsigned> &":$reductionDims),
        /*methodBody=*/"",
        /*defaultImplementation=*/[{
          return failure();
        }]
      >,
      InterfaceMethod<
        /*desc=*/[{
          Method to merge partial reductions for an operation that has been
          tiled along the reduction dimensions. This will only apply the
          reduction the operation.
        }],
        /*retType=*/"::mlir::FailureOr<MergeResult>",
        /*methodName=*/"mergeReductions",
        /*args=*/(ins
            "::mlir::OpBuilder &":$b,
            "Location ":$loc,
            "ValueRange":$partialReduce,
            "const ::mlir::SetVector<unsigned> &":$reductionDims),
        /*methodBody=*/"",
        /*defaultImplementation=*/[{
          return failure();
        }]
      >,
      InterfaceMethod<
        /*desc=*/[{
          Method to return the position of the partial result tile computed by
          the tiled operation. This is same as
          TilingInterface:::getResultTilePosition, but determines the result
          tile position for partial reduction.
        }],
        /*retType=*/"::llvm::LogicalResult",
        /*methodName=*/"getPartialResultTilePosition",
        /*args=*/(ins
            "::mlir::OpBuilder &":$b,
            "unsigned":$resultNumber,
            "::mlir::ArrayRef<::mlir::OpFoldResult> ":$offsets,
            "::mlir::ArrayRef<::mlir::OpFoldResult> ":$sizes,
            "const ::mlir::SetVector<unsigned> &":$reductionDims,
            "::mlir::SmallVector<::mlir::OpFoldResult> &":$resultOffsets,
            "::mlir::SmallVector<::mlir::OpFoldResult> &":$resultSizes),
        /*methodBody=*/"",
        /*defaultImplementation=*/[{
          return failure();
        }]
      >
  ];
}
#endif // MLIR_TILINGINTERFACE
