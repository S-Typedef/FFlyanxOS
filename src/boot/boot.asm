org 0x7c00

    jmp start
    nop

StackBase equ	0x7c00

BootMessage:  db "Booting......"

start:
        mov ax,cs
        mov ds,ax
        mov ss,ax
        mov sp,StackBase

        ;显示字符串
        mov al, 1
        mov bh,0
        mov bl,0x07     ;黑底白字
        mov cx,13
        mov dh,0
        mov dl,0
        ; es=ds
        push ds
        pop es
        mov bp,BootMessage
        mov ah,0x13
        int 0x10

        jmp $

    ; times n,m
    ;        n:重复次数
    ;        m:定义的数据

    times 510-($-$$) db 0
    dw 0xaa55   ;引导扇区标志







