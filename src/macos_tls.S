/* The original guest `mov rax, gs:[0]` only changes RAX. Preserve every other
 * general register, flags, x87/SSE state and AVX upper lanes across the C TLS
 * lookup. The CALL into this shim is emitted only for the exact 9-byte load. */
#ifdef __APPLE__
.text
.globl _bb_macos_guest_tcb
.p2align 4
_bb_macos_guest_tcb:
    pushfq
    pushq %rbx
    pushq %rcx
    pushq %rdx
    pushq %rsi
    pushq %rdi
    pushq %rbp
    pushq %r8
    pushq %r9
    pushq %r10
    pushq %r11
    pushq %r12
    pushq %r13
    pushq %r14
    pushq %r15
    subq $768, %rsp
    fxsave64 (%rsp)
    vextractf128 $1, %ymm0, 512(%rsp)
    vextractf128 $1, %ymm1, 528(%rsp)
    vextractf128 $1, %ymm2, 544(%rsp)
    vextractf128 $1, %ymm3, 560(%rsp)
    vextractf128 $1, %ymm4, 576(%rsp)
    vextractf128 $1, %ymm5, 592(%rsp)
    vextractf128 $1, %ymm6, 608(%rsp)
    vextractf128 $1, %ymm7, 624(%rsp)
    vextractf128 $1, %ymm8, 640(%rsp)
    vextractf128 $1, %ymm9, 656(%rsp)
    vextractf128 $1, %ymm10, 672(%rsp)
    vextractf128 $1, %ymm11, 688(%rsp)
    vextractf128 $1, %ymm12, 704(%rsp)
    vextractf128 $1, %ymm13, 720(%rsp)
    vextractf128 $1, %ymm14, 736(%rsp)
    vextractf128 $1, %ymm15, 752(%rsp)
    callq _runtime_thread_tcb_pointer
    fxrstor64 (%rsp)
    vinsertf128 $1, 512(%rsp), %ymm0, %ymm0
    vinsertf128 $1, 528(%rsp), %ymm1, %ymm1
    vinsertf128 $1, 544(%rsp), %ymm2, %ymm2
    vinsertf128 $1, 560(%rsp), %ymm3, %ymm3
    vinsertf128 $1, 576(%rsp), %ymm4, %ymm4
    vinsertf128 $1, 592(%rsp), %ymm5, %ymm5
    vinsertf128 $1, 608(%rsp), %ymm6, %ymm6
    vinsertf128 $1, 624(%rsp), %ymm7, %ymm7
    vinsertf128 $1, 640(%rsp), %ymm8, %ymm8
    vinsertf128 $1, 656(%rsp), %ymm9, %ymm9
    vinsertf128 $1, 672(%rsp), %ymm10, %ymm10
    vinsertf128 $1, 688(%rsp), %ymm11, %ymm11
    vinsertf128 $1, 704(%rsp), %ymm12, %ymm12
    vinsertf128 $1, 720(%rsp), %ymm13, %ymm13
    vinsertf128 $1, 736(%rsp), %ymm14, %ymm14
    vinsertf128 $1, 752(%rsp), %ymm15, %ymm15
    addq $768, %rsp
    popq %r15
    popq %r14
    popq %r13
    popq %r12
    popq %r11
    popq %r10
    popq %r9
    popq %r8
    popq %rbp
    popq %rdi
    popq %rsi
    popq %rdx
    popq %rcx
    popq %rbx
    popfq
    retq
#endif
