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

        ;操作软盘前，将软驱复位
        xor ah,ah       ;ah置0,速度优于 mov
        xor dl,dl
        int 0x13

        ;在软盘A中寻找文件
        mov word [wSector],SectorNoOfRootDirectory      ;读取软盘的根目录区号
SEARC_FILE_IN_ROOT_DIR_BEGIN:
    cmp word [wRootDirSizeLoop],0
    jz  NO_FILE                     ;读完整个根目录都没找到，没有文件
    dec word [wRootDirSizeLoop];    wRootDirSizeLoop--

    ; 读取扇区
    mov ax,LOADER_SEG
    mov es,ax
    mov bx,LOADER_OFFSET
    mov ax,[wSector]
    mov cl,1

    call ReadSector

    mov si,LoaderFileName   ;ds:si->Loader的文件名
    mov di,LOADER_OFFSET    ;es:si->LOADER_SEG:LOADER_OFFSET->加载到内存中的扇区数据
    cld     ;字符串比较方向。si、di方向向右

    ;开始在扇区中寻找文件，比较文件名
    mov dx,16       ;一个扇区512字节，FAT目录项32字节，512/32=16，一个扇区16个目录项
SEARCH_FOR_FILE:
    cmp dx,0
    jz NEXT_SECTOR_IN_ROOT_DIR       ;读完整个扇区，没有找到，准备加载下一个扇区
    dec dx          ;dx--
    ;开始比较目录项中的文件名
    mov cx,11
CMP_FILENAME:
    cmp cx,0
    jz FILENAME_FOUND   ;cx=0,找到了目标文件
    dec cx              ;cx--
    lodsb               ;ds:si->al,si++
    cmp al,byte [es:di] ;比较字符
    je GO_ON            ;字符相同，准备继续比较下一个
    jmp DIFFERENT       ;不同，跳出

GO_ON:
    inc di
    jmp CMP_FILENAME
DIFFERENT:
    and di,0xfff0
    ; di &= f0, 11111111 11110000，指向本目录项条目的开始
    ; di最大增长到11，将其置零需要低四位归零
    add di,32   ;指向下一个目录项

    mov si,LoaderFileName
    jmp SEARCH_FOR_FILE     ;重新开始比较

NEXT_SECTOR_IN_ROOT_DIR:
    add word [wSector],1    ;准备开始读下一个扇区
    jmp SEARC_FILE_IN_ROOT_DIR_BEGIN
NO_FILE:
    mov dh,2
    call DispStr        ;"NO LOADER!"
    ;死循环
    jmp $
FILENAME_FOUND:
    push es
    mov dh,1
    call DispStr        ;"Loading..."
    pop es

    ;准备参数读书文件数据扇区
    mov ax,RootDirSectors   ;ax=根目录占用空间
    and di,0xfff0
    add di,0x1a             ;FAT目录项0x1a处是文件数据所在的第一个簇号
    mov cx,[es:di]          ;cx=文件数据所在的第一个簇号
    push cx
    ;通过簇号计算真正扇区号
    add cx,ax
    add cx,DeltaSectorNo    ;簇号+根目录占据空间+文件开始扇区号 == 文件数据的第一个扇区
    mov ax,LOADER_SEG
    mov es,ax
    mov bx,LOADER_OFFSET
    mov ax,cx               ;ax = 文件数据的第一个扇区
LOADING_FILE:
    ;每读取一个数据扇区，就在"Loading..."后挨着打印一个点，形成动画
    ;0x10中断，0xe功能：在光标后打印一个字符
    push ax
    push bx
    mov ah,0xe
    mov al,'*'
    mov bl,0x7
    int 0x10
    pop bx
    pop ax

    mov cl,1            ;读一个扇区
    call ReadSector     ;读取

    pop ax              ;取保存的文件的簇号
    call GET_FATEntry   ;通过簇号获取下一个FAT项的值
    cmp ax,0xff8
    jae FILE_LOADED     ;加载完成
    ;未完成循环读取，设置下一次要读取的扇区的参数
    push ax
    ;通过簇号计算真正扇区号
    mov dx,RootDirSectors
    add ax,dx
    add ax,DeltaSectorNo        ;簇号+根目录占据空间+文件开始扇区号 == 文件数据的第一个扇区
    add bx,[BPB_BytsPerSec]     ;bx+=扇区字节量
    jmp LOADING_FILE

FILE_LOADED:
    mov dh,3
        call DispStr                ;"Loaded ^-^"
    ;死循环
    jmp LOADER_SEG:LOADER_OFFSET    ;跳转到Loader程序，引导程序使命结束



;=========================================================
;变量
wRootDirSizeLoop    dw      RootDirSectors  ;根目录占用的扇区数，在循环中将被递减至0
wSector             dw      0               ;要读取的扇区号
isOdd               db      0               ;FAT条目是否奇数


;=======================================================================
;-----------------------------------------------------------------------
LoaderFileName db "LOADER  BIN", 0   ;LOADER.BIN之文件名
;要显示字符串
;简化代码，每个字符串长度均为 MessageLength
MessageLength       equ 10
BootMessage:    db "Booting..."      ;12字节，不够用空格补齐，序号0
                db "Loading..."
                db "NO LOADER!"
                db "Loaded ^-^"
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



;----------------------------------------------------------------------------
; 函数名: ReadSector
;----------------------------------------------------------------------------
; 作用:
;	从第 ax 个 Sector 开始, 将 cl 个 Sector 读入 es:bx 中
ReadSector:
; -----------------------------------------------------------------------
; 怎样由扇区号求扇区在磁盘中的位置 (扇区号 -> 柱面号, 起始扇区, 磁头号)
; -----------------------------------------------------------------------
; 设扇区号为 x
;                           ┌ 柱面号 = y >> 1
;       x           ┌ 商 y ┤
; -------------- => ┤      └ 磁头号 = y & 1
;  每磁道扇区数       │
;                   └ 余 z => 起始扇区号 = z + 1
    push	bp
    mov	bp, sp
    sub	esp, 2			; 辟出两个字节的堆栈区域保存要读的扇区数: byte [bp-2]

    mov	byte [bp-2], cl
    push	bx			; 保存 bx
    mov	bl, [BPB_SecPerTrk]	; bl: 除数
    div	bl			; y 在 al 中, z 在 ah 中
    inc	ah			; z ++
    mov	cl, ah			; cl <- 起始扇区号
    mov	dh, al			; dh <- y
    shr	al, 1			; y >> 1 (其实是 y/BPB_NumHeads, 这里BPB_NumHeads=2)
    mov	ch, al			; ch <- 柱面号
    and	dh, 1			; dh & 1 = 磁头号
    pop	bx			; 恢复 bx
    ; 至此, "柱面号, 起始扇区, 磁头号" 全部得到 ^^^^^^^^^^^^^^^^^^^^^^^^
    mov	dl, [BS_DrvNum]		; 驱动器号 (0 表示 A 盘)
.GoOnReading:
    mov	ah, 2				; 读
    mov	al, byte [bp-2]		; 读 al 个扇区
    int	13h
    jc	.GoOnReading		; 如果读取错误 CF 会被置为 1, 这时就不停地读, 直到正确为止

    add	esp, 2
    pop	bp

    ret

;=======================================================================
; 作用：找到簇号为ax在FAT中的条目，将结果放入ax中
; 加载FAT表的扇区到es:bx处，先保存es:bx
GET_FATEntry:
    push es
    push bx
    ;保存ax值
    push ax
    ;开辟新空间存放FAT表
    mov ax,LOADER_SEG - 0x100
    mov es,ax
    pop ax

    ; 首先计算出簇号在FAT中的字节偏移量，计算奇偶性
    ; 偏移值: 簇号 *3 / 2 的商，3个字节表示2个簇
    mov byte [isOdd],0  ;isOdd = FALSE
    mov bx,3            ;bx=3
    mul bx              ;ax*3 -> 低8位存放在ax
    mov bx,2            ;bx=2
    div bx              ;ax/2->  ax存商，dx存余数
    cmp dx,0
    je EVEN;
    mov byte [isOdd],1  ;isOdd = TRUE
EVEN:
    ;FAT表占9个扇区，簇号5，5/512 =0...5,FAT表中，0扇区中这个簇号所在偏移是5
    ;570 570/512=1...58,FAT表1扇区中这个簇号所在偏移是58
    xor dx,dx                   ;dx=0
    mov bx,[BPB_BytsPerSec]     ;bx = 每扇区字节数
    div bx                      ;ax存商，扇区数，dx存余数，偏移

    push dx                     ;保存偏移
    mov bx,0
    add ax,SectorNoOfFAT1       ;加上FAT第一个扇区号
    mov cl,2                    ;读取两个扇区，避免边界错误问题
    call ReadSector
    pop dx                      ;恢复FAT项在相对于FAT表中的扇区偏移
    add bx,dx                   ;bx+=偏移。得到FAT项在内存中的偏移
    mov ax,[es:bx]              ;ax=簇号对应的FAT项
    cmp byte [isOdd] ,1
    jne EVEN_2
    ;奇数项FAT
    shr ax,4                    ;右移四位（上一项的高四位）
    jmp GET_FATEntry_OK
EVEN_2:                         ;偶数FAT项处理
    and ax,0x0fff               ;高四位（下一个FAT项的低四位）清零
GET_FATEntry_OK:
    pop bx
    pop es
    ret



;=======================================================================
;-----------------------------------------------------------------------
; times n m     n:重复次数，m：重复的代码
    times 510-($-$$) db 0   ;填充剩下的空间，使生成的二进制代码恰好为512字节
    dw 0xaa55               ;可引导扇区结束标志