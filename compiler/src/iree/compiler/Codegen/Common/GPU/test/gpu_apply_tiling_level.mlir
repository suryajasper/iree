// RUN: iree-opt --split-input-file --pass-pipeline="builtin.module(func.func(iree-codegen-gpu-apply-tiling-level, canonicalize, cse))" %s | FileCheck %s
// RUN: iree-opt --split-input-file --pass-pipeline="builtin.module(func.func(iree-codegen-gpu-apply-tiling-level{tiling-level=thread}, canonicalize, cse))" %s | FileCheck %s --check-prefix=THREAD

#config = #iree_gpu.lowering_config<{thread = [2, 16]}>
#map = affine_map<(d0, d1) -> (d0, d1)>
module {
  func.func @add_tensor() {
    %c0 = arith.constant 0 : index
    %0 = hal.interface.binding.subspan set(0) binding(0) type(storage_buffer) alignment(64) offset(%c0) : !flow.dispatch.tensor<readonly:tensor<64x256xf32>>
    %1 = hal.interface.binding.subspan set(0) binding(1) type(storage_buffer) alignment(64) offset(%c0) : !flow.dispatch.tensor<readonly:tensor<64x256xf32>>
    %2 = hal.interface.binding.subspan set(0) binding(2) type(storage_buffer) alignment(64) offset(%c0) : !flow.dispatch.tensor<writeonly:tensor<64x256xf32>>
    %3 = flow.dispatch.tensor.load %0, offsets = [%c0, %c0], sizes = [64, 256], strides = [1, 1] : !flow.dispatch.tensor<readonly:tensor<64x256xf32>> -> tensor<64x256xf32>
    %4 = flow.dispatch.tensor.load %1, offsets = [%c0, %c0], sizes = [64, 256], strides = [1, 1] : !flow.dispatch.tensor<readonly:tensor<64x256xf32>> -> tensor<64x256xf32>
    %5 = flow.dispatch.tensor.load %2, offsets = [%c0, %c0], sizes = [64, 256], strides = [1, 1] : !flow.dispatch.tensor<writeonly:tensor<64x256xf32>> -> tensor<64x256xf32>
    %6 = linalg.generic {
      indexing_maps = [#map, #map, #map],
      iterator_types = ["parallel", "parallel"]
      } ins(%3, %4 : tensor<64x256xf32>, tensor<64x256xf32>) outs(%5 : tensor<64x256xf32>) attrs =  {lowering_config = #config} {
    ^bb0(%in: f32, %in_0: f32, %out: f32):
      %7 = arith.addf %in, %in_0 : f32
      linalg.yield %7 : f32
    } -> tensor<64x256xf32>
    flow.dispatch.tensor.store %6, %2, offsets = [%c0, %c0], sizes = [64, 256], strides = [1, 1] : tensor<64x256xf32> -> !flow.dispatch.tensor<writeonly:tensor<64x256xf32>>
    return
  }
}

// Verify that no loops are generated without a reduction configuration.
// CHECK-LABEL: func.func @add_tensor
//   CHECK-NOT:   scf.for

// THREAD-LABEL: func.func @add_tensor
//       THREAD:   scf.forall ({{.*}}) = (0, 0) to (64, 256) step (2, 16)
//       THREAD:     linalg.generic {{.*}} ins(%{{.*}}: tensor<2x16xf32>, tensor<2x16xf32>)
//       THREAD:     scf.forall.in_parallel
//       THREAD:   mapping = [#gpu.thread<linear_dim_0>, #gpu.thread<linear_dim_1>]

// -----

#config = #iree_gpu.lowering_config<{reduction = [0, 8]}>
#map = affine_map<()[s0] -> (s0 * 64)>
#map1 = affine_map<(d0, d1) -> (d0, d1)>
#map2 = affine_map<(d0, d1) -> (d0)>
module {
  func.func @reduction() {
    %c0 = arith.constant 0 : index
    %cst = arith.constant 0.000000e+00 : f32
    %0 = hal.interface.binding.subspan set(0) binding(0) type(storage_buffer) alignment(64) offset(%c0) : !flow.dispatch.tensor<readonly:tensor<128x384xf32>>
    %1 = hal.interface.binding.subspan set(0) binding(1) type(storage_buffer) alignment(64) offset(%c0) : !flow.dispatch.tensor<writeonly:tensor<128xf32>>
    %3 = flow.dispatch.tensor.load %0, offsets = [0, 0], sizes = [128, 384], strides = [1, 1] : !flow.dispatch.tensor<readonly:tensor<128x384xf32>> -> tensor<128x384xf32>
    %empty = tensor.empty() : tensor<128xf32>
    %4 = linalg.fill ins(%cst : f32) outs(%empty : tensor<128xf32>) -> tensor<128xf32>
    %5 = linalg.generic {
      indexing_maps = [#map1, #map2],
      iterator_types = ["parallel", "reduction"]
      } ins(%3 : tensor<128x384xf32>) outs(%4 : tensor<128xf32>) attrs =  {lowering_config = #config} {
    ^bb0(%in: f32, %out: f32):
      %7 = arith.addf %in, %out : f32
      linalg.yield %7 : f32
    } -> tensor<128xf32>
    flow.dispatch.tensor.store %5, %1, offsets = [%c0], sizes = [128], strides = [1] : tensor<128xf32> -> !flow.dispatch.tensor<writeonly:tensor<128xf32>>
    return
  }
}

// CHECK-LABEL: func.func @reduction
//       CHECK:   %[[FILL:.+]] = linalg.fill {{.*}} tensor<128xf32>
//       CHECK:   scf.for %{{.*}} = %c0 to %c384 step %c8 iter_args(%{{.*}} = %[[FILL]])
//       CHECK:     linalg.generic {{.*}} ins(%{{.*}} : tensor<128x8xf32>)
//       CHECK:     scf.yield

// Verify that no tiling happens in the thread case.
// THREAD-LABEL: func.func @reduction
//   THREAD-NOT:   scf.forall

// -----

#config = #iree_gpu.lowering_config<{reduction = [0, 0, 8]}>
#map = affine_map<(d0, d1) -> (d0, d1)>
module {
  func.func @matmul_fuse() {
    %c0 = arith.constant 0 : index
    %cst = arith.constant 1.0 : f32
    %0 = hal.interface.binding.subspan set(0) binding(0) type(storage_buffer) alignment(64) offset(%c0) : !flow.dispatch.tensor<readonly:tensor<64x64xf32>>
    %1 = hal.interface.binding.subspan set(0) binding(1) type(storage_buffer) alignment(64) offset(%c0) : !flow.dispatch.tensor<readonly:tensor<64x64xf32>>
    %2 = hal.interface.binding.subspan set(0) binding(2) type(storage_buffer) alignment(64) offset(%c0) : !flow.dispatch.tensor<writeonly:tensor<64x64xf32>>
    %3 = flow.dispatch.tensor.load %0, offsets = [%c0, %c0], sizes = [64, 64], strides = [1, 1] : !flow.dispatch.tensor<readonly:tensor<64x64xf32>> -> tensor<64x64xf32>
    %4 = flow.dispatch.tensor.load %1, offsets = [%c0, %c0], sizes = [64, 64], strides = [1, 1] : !flow.dispatch.tensor<readonly:tensor<64x64xf32>> -> tensor<64x64xf32>
    %5 = flow.dispatch.tensor.load %2, offsets = [%c0, %c0], sizes = [64, 64], strides = [1, 1] : !flow.dispatch.tensor<writeonly:tensor<64x64xf32>> -> tensor<64x64xf32>
    %empty = tensor.empty() : tensor<64x64xf32>
    %6 = linalg.generic {
      indexing_maps = [#map, #map],
      iterator_types = ["parallel", "parallel"]
      } ins(%3 : tensor<64x64xf32>) outs(%empty : tensor<64x64xf32>) {
    ^bb0(%in: f32, %out: f32):
      %8 = arith.addf %in, %cst : f32
      linalg.yield %8 : f32
    } -> tensor<64x64xf32>
    %7 = linalg.matmul {lowering_config = #config} ins(%6, %4 : tensor<64x64xf32>, tensor<64x64xf32>) outs(%5 : tensor<64x64xf32>) -> tensor<64x64xf32>
    flow.dispatch.tensor.store %7, %2, offsets = [%c0, %c0], sizes = [64, 64], strides = [1, 1] : tensor<64x64xf32> -> !flow.dispatch.tensor<writeonly:tensor<64x64xf32>>
    return
  }
}

// CHECK-LABEL: func.func @matmul_fuse
//       CHECK:   scf.for %{{.*}} = %c0 to %c64 step %c8
//       CHECK:     %[[ELEMWISE:.+]] = linalg.generic {{.*}} ins(%{{.*}} : tensor<64x8xf32>)
//       CHECK:     %[[MM:.+]] = linalg.matmul {{.*}} ins(%[[ELEMWISE]], {{.*}} : tensor<64x8xf32>, tensor<8x64xf32>)
