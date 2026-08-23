# x86_64 macOS (Darwin) freestanding stub.
# argv[0] is .../ChurchGuestZoom.app/Contents/MacOS/ChurchGuestZoom
# execve /bin/bash .../Contents/Resources/launch.command
.globl _start
_start:
    movq 8(%rsp), %rsi              /* argv[0] */
    subq $0x1000, %rsp              /* path buffer */
    movq %rsp, %rdi
    /* copy argv[0] into buffer, cap ~4000 */
    xorl %ecx, %ecx
copy:
    movb (%rsi,%rcx), %al
    movb %al, (%rdi,%rcx)
    incl %ecx
    cmpl $4000, %ecx
    jae strip
    testb %al, %al
    jne copy
strip:
    /* strip filename: last '/' -> 0, then restore slash and cut at MacOS */
    movl %ecx, %edx
find1:
    decl %edx
    js fail
    cmpb $'/', (%rdi,%rdx)
    jne find1
    /* rdi+rdx = slash before filename. Cut filename. */
    movb $0, (%rdi,%rdx)
    /* now .../MacOS ; strip MacOS */
    movl %edx, %ecx
find2:
    decl %ecx
    js fail
    cmpb $'/', (%rdi,%rcx)
    jne find2
    /* rdi+rcx = slash before MacOS. Keep it, write Resources/launch.command after */
    incq %rcx
    leaq suffix(%rip), %rsi
sfx:
    movb (%rsi), %al
    movb %al, (%rdi,%rcx)
    incq %rsi
    incq %rcx
    testb %al, %al
    jne sfx
    /* execve("/bin/bash", ["/bin/bash", path, NULL], NULL) */
    leaq bash(%rip), %rdi
    movq %rsp, %rsi                 /* path is at rsp */
    /* argv array at rsp-32 */
    leaq -32(%rsp), %r8
    movq %rdi, 0(%r8)
    movq %rsi, 8(%r8)
    movq $0, 16(%r8)
    movq %r8, %rsi                  /* argv */
    xorl %edx, %edx                 /* envp NULL */
    movl $0x200003b, %eax           /* execve */
    syscall
fail:
    movl $0x2000001, %eax           /* exit */
    movl $42, %edi
    syscall
    jmp fail

bash:
    .asciz "/bin/bash"
suffix:
    .asciz "Resources/launch.command"
