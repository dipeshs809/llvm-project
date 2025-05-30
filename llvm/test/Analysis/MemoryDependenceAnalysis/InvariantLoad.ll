; NOTE: Assertions have been autogenerated by utils/update_test_checks.py
; RUN: opt < %s -passes=gvn -S | FileCheck %s

target datalayout = "e-m:e-i64:64-f80:128-n8:16:32:64-S128-ni:1"
target triple = "x86_64-unknown-linux-gnu"

declare void @llvm.memset.p0.i8(ptr, i8, i32, i1)
declare void @foo(ptr)

define i8 @test(i1 %cmp) {
; CHECK-LABEL: @test(
; CHECK-NEXT:  entry:
; CHECK-NEXT:    [[P:%.*]] = alloca i8
; CHECK-NEXT:    store i8 5, ptr [[P]]
; CHECK-NEXT:    br label [[HEADER:%.*]]
; CHECK:       header:
; CHECK-NEXT:    [[V:%.*]] = phi i8 [ 5, [[ENTRY:%.*]] ], [ -5, [[ALIVE:%.*]] ]
; CHECK-NEXT:    [[I:%.*]] = phi i8 [ 0, [[ENTRY]] ], [ [[I_INC:%.*]], [[ALIVE]] ]
; CHECK-NEXT:    br i1 [[CMP:%.*]], label [[ALIVE]], label [[DEAD:%.*]]
; CHECK:       dead:
; CHECK-NEXT:    call void @foo(ptr [[P]])
; CHECK-NEXT:    [[I_1:%.*]] = add i8 [[I]], [[V]]
; CHECK-NEXT:    br label [[ALIVE]]
; CHECK:       alive:
; CHECK-NEXT:    [[I_2:%.*]] = phi i8 [ [[I]], [[HEADER]] ], [ [[I_1]], [[DEAD]] ]
; CHECK-NEXT:    store i8 -5, ptr [[P]]
; CHECK-NEXT:    call void @llvm.memset.p0.i32(ptr align 1 [[P]], i8 0, i32 1, i1 false)
; CHECK-NEXT:    [[I_INC]] = add i8 [[I_2]], 1
; CHECK-NEXT:    [[CMP_LOOP:%.*]] = icmp ugt i8 [[I_INC]], 100
; CHECK-NEXT:    br i1 [[CMP_LOOP]], label [[EXIT:%.*]], label [[HEADER]]
; CHECK:       exit:
; CHECK-NEXT:    ret i8 0
;

entry:
  %p = alloca i8
  store i8 5, ptr %p
  br label %header
header:
  %i = phi i8 [0, %entry], [%i.inc, %backedge]
  br i1 %cmp, label %alive, label %dead
dead:
  call void @foo(ptr %p)
  %v = load i8, ptr %p, !invariant.load !1
  %i.1 = add i8 %i, %v
  br label %alive
alive:
  %i.2 = phi i8 [%i, %header], [%i.1, %dead]
  store i8 -5, ptr %p
  br label %backedge
backedge:
  call void @llvm.memset.p0.i8(ptr align 1 %p, i8 0, i32 1, i1 false)
  %i.inc = add i8 %i.2, 1
  %cmp.loop = icmp ugt i8 %i.inc, 100
  br i1 %cmp.loop, label %exit, label %header
exit:
  %res = load i8, ptr %p
  ret i8 %res
}

; Check that first two loads are not optimized out while the one marked with
; invariant.load reuses %res1
define i8 @test2(i1 %cmp, ptr %p) {
; CHECK-LABEL: @test2(
; CHECK-NEXT:  entry:
; CHECK-NEXT:    [[RES1:%.*]] = load i8, ptr [[P:%.*]], align 1
; CHECK-NEXT:    call void @foo(ptr [[P]])
; CHECK-NEXT:    br i1 [[CMP:%.*]], label [[B2:%.*]], label [[B1:%.*]]
; CHECK:       b1:
; CHECK-NEXT:    [[RES2:%.*]] = load i8, ptr [[P]]
; CHECK-NEXT:    [[RES3:%.*]] = add i8 [[RES1]], [[RES2]]
; CHECK-NEXT:    br label [[ALIVE:%.*]]
; CHECK:       b2:
; CHECK-NEXT:    [[RES_DEAD:%.*]] = add i8 [[RES1]], [[RES1]]
; CHECK-NEXT:    br label [[ALIVE]]
; CHECK:       alive:
; CHECK-NEXT:    [[RES_PHI:%.*]] = phi i8 [ [[RES3]], [[B1]] ], [ [[RES_DEAD]], [[B2]] ]
; CHECK-NEXT:    ret i8 [[RES_PHI]]
;

entry:
  %res1 = load i8, ptr %p
  call void @foo(ptr %p)
  br i1 %cmp, label %b2, label %b1
b1:
  %res2 = load i8, ptr %p
  %res3 = add i8 %res1, %res2
  br label %alive
b2:
  %v = load i8, ptr %p, !invariant.load !1
  %res.dead = add i8 %v, %res1
  br label %alive
alive:
  %res.phi = phi i8 [%res3, %b1], [%res.dead, %b2]
  ret i8 %res.phi
}

; This is essentially the same test case as the above one but with %b1 and %b2
; swapped in "br i1 %cmp, label %b1, label %b2" instruction. That helps us to
; ensure that results doesn't depend on visiting order.
define i8 @test3(i1 %cmp, ptr %p) {
; CHECK-LABEL: @test3(
; CHECK-NEXT:  entry:
; CHECK-NEXT:    [[RES1:%.*]] = load i8, ptr [[P:%.*]], align 1
; CHECK-NEXT:    call void @foo(ptr [[P]])
; CHECK-NEXT:    br i1 [[CMP:%.*]], label [[B1:%.*]], label [[B2:%.*]]
; CHECK:       b1:
; CHECK-NEXT:    [[RES2:%.*]] = load i8, ptr [[P]]
; CHECK-NEXT:    [[RES3:%.*]] = add i8 [[RES1]], [[RES2]]
; CHECK-NEXT:    br label [[ALIVE:%.*]]
; CHECK:       b2:
; CHECK-NEXT:    [[RES_DEAD:%.*]] = add i8 [[RES1]], [[RES1]]
; CHECK-NEXT:    br label [[ALIVE]]
; CHECK:       alive:
; CHECK-NEXT:    [[RES_PHI:%.*]] = phi i8 [ [[RES3]], [[B1]] ], [ [[RES_DEAD]], [[B2]] ]
; CHECK-NEXT:    ret i8 [[RES_PHI]]
;
entry:
  %res1 = load i8, ptr %p
  call void @foo(ptr %p)
  br i1 %cmp, label %b1, label %b2
b1:
  %res2 = load i8, ptr %p
  %res3 = add i8 %res1, %res2
  br label %alive
b2:
  %v = load i8, ptr %p, !invariant.load !1
  %res.dead = add i8 %v, %res1
  br label %alive
alive:
  %res.phi = phi i8 [%res3, %b1], [%res.dead, %b2]
  ret i8 %res.phi
}


; This is reduced test case catching regression in the first version of the
; fix for invariant loads (https://reviews.llvm.org/D64405).
define void @test4() null_pointer_is_valid {
; CHECK-LABEL: @test4(
; CHECK-NEXT:  entry:
; CHECK-NEXT:    [[TMP0:%.*]] = load float, ptr inttoptr (i64 8 to ptr), align 4
; CHECK-NEXT:    [[TMP1:%.*]] = fmul float [[TMP0]], [[TMP0]]
; CHECK-NEXT:    br label [[FUSION_LOOP_HEADER_DIM_1_PREHEADER:%.*]]
; CHECK:       fusion.loop_header.dim.1.preheader:
; CHECK-NEXT:    [[TMP2:%.*]] = phi float [ [[TMP0]], [[ENTRY:%.*]] ], [ [[DOTPRE:%.*]], [[FUSION_LOOP_HEADER_DIM_1_PREHEADER]] ]
; CHECK-NEXT:    [[FUSION_INVAR_ADDRESS_DIM_0_03:%.*]] = phi i64 [ 0, [[ENTRY]] ], [ [[INVAR_INC3:%.*]], [[FUSION_LOOP_HEADER_DIM_1_PREHEADER]] ]
; CHECK-NEXT:    [[TMP3:%.*]] = getelementptr inbounds [2 x [1 x [4 x float]]], ptr null, i64 0, i64 [[FUSION_INVAR_ADDRESS_DIM_0_03]], i64 0, i64 2
; CHECK-NEXT:    [[TMP4:%.*]] = fmul float [[TMP2]], [[TMP2]]
; CHECK-NEXT:    [[INVAR_INC3]] = add nuw nsw i64 [[FUSION_INVAR_ADDRESS_DIM_0_03]], 1
; CHECK-NEXT:    [[DOTPHI_TRANS_INSERT:%.*]] = getelementptr inbounds [2 x [1 x [4 x float]]], ptr null, i64 0, i64 [[INVAR_INC3]], i64 0, i64 2
; CHECK-NEXT:    [[DOTPRE]] = load float, ptr [[DOTPHI_TRANS_INSERT]], align 4, !invariant.load !0
; CHECK-NEXT:    br label [[FUSION_LOOP_HEADER_DIM_1_PREHEADER]]
;
entry:
  %0 = getelementptr inbounds [2 x [1 x [4 x float]]], ptr null, i64 0, i64 0, i64 0, i64 2
  %1 = load float, ptr %0, align 4
  %2 = fmul float %1, %1
  br label %fusion.loop_header.dim.1.preheader

fusion.loop_header.dim.1.preheader:               ; preds = %fusion.loop_header.dim.1.preheader, %entry
  %fusion.invar_address.dim.0.03 = phi i64 [ 0, %entry ], [ %invar.inc3, %fusion.loop_header.dim.1.preheader ]
  %3 = getelementptr inbounds [2 x [1 x [4 x float]]], ptr null, i64 0, i64 %fusion.invar_address.dim.0.03, i64 0, i64 2
  %4 = load float, ptr %3, align 4, !invariant.load !1
  %5 = fmul float %4, %4
  %6 = getelementptr inbounds [2 x [1 x [4 x float]]], ptr null, i64 0, i64 %fusion.invar_address.dim.0.03, i64 0, i64 2
  %7 = load float, ptr %6, align 4, !invariant.load !1
  %8 = fmul float %7, %7
  %invar.inc3 = add nuw nsw i64 %fusion.invar_address.dim.0.03, 1
  br label %fusion.loop_header.dim.1.preheader
}

!1 = !{}
