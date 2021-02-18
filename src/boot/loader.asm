org 0x100
    jmp start
BaseOfStack equ 0x100   ;调试状态
;=======================================================================
;   16位实模式代码段
;-----------------------------------------------------------------------
start:
    ;寄存器复位
    mov ax,cs
    mov ds,ax
    mov es,ax
    mov ss,ax
    mov sp,BaseOfStack

    ;显示字符串 "Hello Loader!"
    mov dh,0                ;"Hello Loader!"
    call DispStr            ;显示字符串

    ;检查内存信息
    mov ebx,0               ;放置“得到后续的内存信息的值”，第一次调用必须为0
    mov di,_MemChkBuf       ;es:di指向准备写入ards的缓冲区地址
MemChkLoop:
    mov eax,0x0000e820
    mov ecx,20              ;ARDS大小
    mov edx,0x0534d4150     ;SMAP
    int 0x15
    jc MemChkFail           ;产生了一个进位，判断CF为1 则出现错误
    ;CF=0,检查成功
    add di,20               ;es:di指向缓冲区准备放入下一个ARDS
    inc dword [_ddMCRCount] ;ARDS数量++
    cmp ebx,0
    je MemChkFinish         ;ebx==0,到达最后一个
    ;未拿到最后一个
    jmp MemChkLoop
MemChkFail:
    mov dword [_ddMCRCount],0     ;检查失败，ARDS数量设置为0
    mov dh,1
    call DispStr            ;检查失败打印"Mem Chk Fail!"


    ;死循环
    jmp $
MemChkFinish:
    mov dh,2
    call DispStr            ;检查成功打印"Mem  Check OK"


    ;死循环
    jmp $


    ;-----------------------------------------------------------------------
    ;要显示字符串
    LoaderFileName  db      "LOADER BIN", 0   ;LOADER.BIN之文件名
    ;简化代码，每个字符串长度均为 MessageLength
    MessageLength       equ 13
    Message:        db      "Hello Loader!"      ;13字节，不够用空格补齐，序号0
                    db      "Mem Chk Fail!"
                    db      "Mem Check OK!"
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
;=======================================================================
;   32位数据段
;-----------------------------------------------------------------------
[section .data32]
align 32
DATA32:
;=======================================================================
;   16位实模式下的数据地址符号
;-----------------------------------------------------------------------
_ddMCRCount:        dd      0          ;memory check result,为0代表检查失败
_ddMemSize:         dd      0          ;内存大小
;地址范围描述符结构(Address Range Descriptor Structure)
_ARDS:
    _ddbaseAddrLow      dd      0       ;基地址低32位
    _ddbaseAddrHigh     dd      0       ;基地址高32位
    _ddLengthLow        dd      0       ;内存长度 字节 低32位
    _ddLengthHigh       dd      0       ;内存长度 字节 高32位
    _ddType             dd      0       ;ARDS类型，判断是否可以被OS使用
;内存检查结果缓冲区，用于存放内存检查的ARDS结构，256字节对齐32位
; 256/32 == 12.8,可以存放12个ARDS
_MemChkBuf  times 256   db      0       ;


;=======================================================================
;   32位模式下的数据地址符号
;-----------------------------------------------------------------------

;=======================================================================