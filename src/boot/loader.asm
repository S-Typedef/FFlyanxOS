org 0x100
    jmp start
    BaseOfStack equ 0x100   ;调试状态

start:
    mov ax,cs
    mov ds,ax
    mov ss,ax
    mov sp,BaseOfStack

    ;显示字符串 "Hello LOader!"
    mov dh,0        ;"Hello LOader!"
    call DispStr     ;显示字符串

    ;死循环
    jmp $


    ;-----------------------------------------------------------------------
    ;要显示字符串
    LoaderFileName  db      "LOADER BIN", 0   ;LOADER.BIN之文件名
    ;简化代码，每个字符串长度均为 MessageLength
    MessageLength       equ 13
    Message:        db      "Hello Loader!"      ;13字节，不够用空格补齐，序号0
    ;=======================================================================
    ;-----------------------------------------------------------------------
    ;函数名：DispStr
    ;-----------------------------------------------------------------------
    ; 作用:
    ;   显示一个字符串，函数开始时， dh中应该是字符串序号（0-based）
    DispStr:
        mov ax,MessageLength
        mul dh
        add ax,Message
        ;ES:BP = 串地址
        mov bp,ax
        mov ax,ds
        mov es,ax
        mov cx,MessageLength    ; CS =  串长度
        mov ax,01301h           ; AH = 13 ,AL = 01h
        mov bx,0007h            ;页号为0(BH=0) 黑底白字(BL = 07h)
        mov dl,0
        int 10h
        ret
