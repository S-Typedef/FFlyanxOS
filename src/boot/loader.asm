org 0x100
    jmp start


;=======================================================================
;   导入头文件
;-----------------------------------------------------------------------
%include    "load.inc"          ;挂载点相关信息
%include    "fat12hdr.inc"      ;需要加载内核文件
%include    "pm.inc"            ;保护模式信息，各种宏和变量
;============================================================================
;   GDT全局描述符表相关信息以及堆栈信息
;----------------------------------------------------------------------------
; 描述符                        基地址        段界限       段属性
LABEL_GDT:			Descriptor	0,          0,          0							; 空描述符，必须存在，不然CPU无法识别GDT
LABEL_DESC_CODE:	Descriptor	0,          0xfffff,    DA_32 | DA_CR | DA_LIMIT_4K	; 0~4G，32位可读代码段，粒度为4KB
LABEL_DESC_DATA:    Descriptor  0,          0xfffff,    DA_32 | DA_DRW | DA_LIMIT_4K; 0~4G，32位可读写数据段，粒度为4KB
LABEL_DESC_VIDEO:   Descriptor  0xb8000,    0xfffff,    DA_DRW | DA_DPL3            ; 视频段，特权级3（用户特权级）
; GDT全局描述符表 -------------------------------------------------------------
GDTLen              equ $ - LABEL_GDT                           ; GDT的长度
GDTPtr              dw GDTLen - 1                               ; GDT指针.段界限
                    dd LOADER_PHY_ADDR + LABEL_GDT              ; GDT指针.基地址
; GDT选择子 ------------------------------------------------------------------
SelectorCode        equ LABEL_DESC_CODE - LABEL_GDT             ; 代码段选择子
SelectorData        equ LABEL_DESC_DATA - LABEL_GDT             ; 数据段选择子
SelectorVideo       equ LABEL_DESC_VIDEO - LABEL_GDT | SA_RPL3  ; 视频段选择子，特权级3（用户特权级）
; GDT选择子 ------------------------------------------------------------------
BaseOfStack	        equ	0x100                                   ; 基栈
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

    ;显示字符串 "Loading..."
    mov dh,0                ;"Loading..."
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
    mov dh,2
    call DispStr            ;检查失败打印"Mem Chk Fail!"

    ;死循环
    jmp $
MemChkFinish:
    ; 操作软盘前，现将软驱复位
    xor ah, ah          ; xor:异或，ah = 0
    xor dl, dl          ; dl = 0
    int 0x13

    ;在软盘A中寻找文件
    mov word [wSector],SectorNoOfRootDirectory      ;读取软盘的根目录区号
SEARC_FILE_IN_ROOT_DIR_BEGIN:
    cmp word [wRootDirSizeLoop],0
    jz  NO_FILE                     ;读完整个根目录都没找到，没有文件
    dec word [wRootDirSizeLoop];    wRootDirSizeLoop--

    ; 读取扇区
    mov ax,KERNEL_SEG
    mov es,ax
    mov bx,KERNEL_OFFSET
    mov ax,[wSector]
    mov cl,1

    call ReadSector

    mov si,KernelFileName   ;ds:si->KERNEL的文件名
    mov di,KERNEL_OFFSET    ;es:si->KERNEL_SEG:KERNEL_OFFSET->加载到内存中的扇区数据
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

    mov si,KernelFileName
    jmp SEARCH_FOR_FILE     ;重新开始比较

NEXT_SECTOR_IN_ROOT_DIR:
    add word [wSector],1    ;准备开始读下一个扇区
    jmp SEARC_FILE_IN_ROOT_DIR_BEGIN
NO_FILE:
    mov dh,2
    call DispStr        ;"NO KERNEL"
    ;死循环
    jmp $
FILENAME_FOUND:
    ;准备参数读书文件数据扇区
    mov ax,RootDirSectors   ;ax=根目录占用空间
    and di,0xfff0

    push eax
    mov eax,[es:di+0x1c]
    mov dword   [dwKernelSize],eax
    cmp eax,KERNEL_HAVE_SPACE
    ja KERNEL_FILE_TOO_LARGE
    pop eax
    jmp FILE_START_LAOD
KERNEL_FILE_TOO_LARGE:
    mov dh,3
    call DispStr
    jmp $
FILE_START_LOAD:
    add di,0x1a             ;FAT目录项0x1a处是文件数据所在的第一个簇号
    mov cx,[es:di]          ;cx=文件数据所在的第一个簇号
    push cx
    ;通过簇号计算真正扇区号
    add cx,ax
    add cx,DeltaSectorNo    ;簇号+根目录占据空间+文件开始扇区号 == 文件数据的第一个扇区
    mov ax,KERNEL_SEG
    mov es,ax
    mov bx,KERNEL_OFFSET
    mov ax,cx               ;ax = 文件数据的第一个扇区
LOADING_FILE:
    ;每读取一个数据扇区，就在"Loading..."后挨着打印一个'*'，形成动画
    ;0x10中断，0xe功能：在光标后打印一个字符
    push ax
    push bx
    mov ah,0xe
    mov al,'*'
    mov bl,0xf
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
    ja KERNEL_GREAT_64KB
    jmp CONTINUE_LOADING
KERNEL_GREAT_64KB:
    push ax
    mov ax,es
    add ax,0x1000
    mov es,ax
    pop ax
CONTINUE_LOADING:
    jmp LOADING_FILE
FILE_LOADED:
    call KillMotor
    mov dh,1
    call DispStr    ; 打印"KERNEL OK!"
;----------------------------------------------------------------------------
; 准备进入32位保护模式
;----------------------------------------------------------------------------
    ; 1 首先，进入保护模式必须有 GDT 全局描述符表，我们加载 gdtr（gdt地址指针）
    lgdt	[GDTPtr]

    ; 2 由于保护模式中断处理的方式和实模式不一样，所以我们需要先关闭中断，否则会引发错误
    cli

    ; 3 打开地址线A20，不打开也可以进入保护模式，但内存寻址能力受限（1MB）
    in al, 92h
    or al, 00000010b
    out 92h, al

    ; 4 进入16位保护模式，设置cr0的第0位：PE（保护模式标志）为1
    mov eax, cr0
    or 	eax, 1
    mov cr0, eax

    ; 5 真正进32位入保护模式！前面的4步已经进入了保护模式
    ; 	现在只需要跳入到一个32位代码段就可以真正进入32位保护模式了！
    jmp dword SelectorCode:LOADER_PHY_ADDR + PM_32_START

    ; 如果上面一切顺利，这一行永远不可能执行的到
    jmp $
;============================================================================
; 变量
wRootDirSizeLoop    dw      RootDirSectors  ; 根目录占用的扇区数，在循环中将被被逐步递减至0
wSector             dw      0               ; 要读取的扇区号
isOdd               db      0               ; 读取的FAT条目是不是奇数项?
dwKernelSize        dd      0               ; 内核文件的大小
;============================================================================
; 要显示的字符串
;----------------------------------------------------------------------------
KernelFileName  db      "KERNEL  BIN", 0   ;KERNEL.BIN之文件名
;简化代码，每个字符串长度均为 MessageLength
MessageLength   equ 10
Message:        db      "Loading..."        ;10字节，不够用空格补齐，序号0
                db      "KERNEL OK!"        ;1
                db      "MemChkFail"        ;2
                db      "Too large!"        ;3
                db      "NO KERNEL!"        ;4
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

;============================================================================
;----------------------------------------------------------------------------
; 函数名: KillMotor
;----------------------------------------------------------------------------
; 作用:
;	关闭软驱马达，有时候软驱读取完如果不关闭马达，马达会持续运行且发出声音
KillMotor:
    push	dx
    mov	dx, 03F2h
    mov	al, 0
    out	dx, al
    pop	dx
    ret
;=======================================================================
;   32位数据段
;-----------------------------------------------------------------------
[section .code32]
align 32
[bits 32]
PM_32_START:            ; 跳转到这里，说明已经进入32位保护模式
    mov ax, SelectorData
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov ss, ax              ; ds = es = fs = ss = 数据段
    mov esp, TopOfStack     ; 设置栈顶
    mov ax, SelectorVideo
    mov gs, ax              ; gs = 视频段

    ; 打印一些字符，自己操作显存，将字符写入到显存中
    ; 显示 "PM" 在第 9 行第 0 列
    mov edi, (80 * 9 + 0) * 2	; 屏幕第 9 行，第 0 列。
    mov ah, 0xC                 ; 0000：黑底	1100：红字
    mov al, 'P'
    mov word [gs:edi], ax       ; 将'P'写入屏幕第 9 行，第 0 列。
    add edi , 2                 ; edi + 2，指向下一列
    mov al, 'M'
    mov word [gs:edi], ax       ; 将'M'写入屏幕第 9 行，第 1 列。

    ; 死循环
    jmp $
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
_MemChkBuf  times 256   db      0

;----------------------------------------------------------------------------
;   32位模式下的数据地址符号
;----------------------------------------------------------------------------

; 堆栈就在数据段的末尾，一共给这个32位代码段堆栈分配4KB
StackSpace: times 0x1000    db 0
TopOfStack  equ LOADER_PHY_ADDR + $     ; 栈顶
;============================================================================