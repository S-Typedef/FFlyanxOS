; 引导程序，加载FlyanxOS的第一步 ：boot 其做一些系统的初始化工作，然后寻找启动盘中的Loader.并加载他
;====================================================================================
;%define   _BOOT_DEBUG_     ;做 BOOT Sector 时一定将此行注释掉！此行打开后用 nasm Boot.asm -o Boot.com 做成一个.COM文件易于调试
%ifdef _BOOT_DEBUG_
    org 0x100               ; 调试状态，做成.COM文件，可调试
%else
    org 7c00h             ; Boot状态，Bios将把 Boot Sector 加载到0:7c00处执行
%endif

;LOADER加载的段地址
LOADER_SEG      equ 0x9000
LOADER_OFFSET   equ 0x100

;=====================================================================================
%ifdef _BOOT_DEBUG_
    BaseOfStack equ 0100h   ;调试状态
%else
    BaseOfStack equ 07c00h  ;Boot状态
%endif
;======================================================================================

    jmp short LABEL_START   ;跳转到程序开始处
    nop                     ;不可省略
    ;导入FAT12头及相关常量信息
    %include "fat12hdr.inc"
;======================================================================================
LABEL_START:
        mov ax,cs
        mov ds,ax
        mov ss,ax
        mov sp,BaseOfStack

        ;清屏，清理BIOS输出
        mov ax,0x0600   ;AH=6,AL=0h
        mov bx,0x0700   ;黑底白字(BL=07H)
        mov cx,0        ;左上角:(0,0)
        mov dx,0x0184f  ;右下角:(88,50)
        int 0x10

        ;显示字符串 "Booting......"
        mov dh,0        ;"Booting......"
        call DispStr     ;显示字符串

        ;死循环
        jmp $
    ;=======================================================================
    ;-----------------------------------------------------------------------
    ;要显示字符串
    LoaderFileName db "LODAER BIN", 0   ;LOADER.BIN之文件名
    ;简化代码，每个字符串长度均为 MessageLength
    MessageLength       equ 12
    BootMessage:    db "Booting......"      ;12字节，不够用空格补齐，序号0
    ;=======================================================================
    ;-----------------------------------------------------------------------
    ;函数名：DispStr
    ;-----------------------------------------------------------------------
    ; 作用:
    ;   显示一个字符串，函数开始时， dh中应该是字符串序号（0-based）
    DispStr:
        mov ax,MessageLength
        mul dh
        add ax,BootMessage
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
    ;-----------------------------------------------------------------------
    ; times n m     n:重复次数，m：重复的代码
    times 510-($-$$) db 0   ;填充剩下的空间，使生成的二进制代码恰好为512字节
    dw 0xaa55               ;可引导扇区结束标志