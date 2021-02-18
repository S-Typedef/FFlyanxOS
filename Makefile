#==================================================================
# 变量
#------------------------------------------------------------------
# 编译连接中间目录
t = target
tb = $(t)/boot
tk = $(t)/kernel

# 所需软盘镜像
os = typedef.img

# 硬盘镜像 -- 还没有



# 镜像挂载点，自指定，不存在就自己创建：mkdir

ImgMountPoint = /media/os


# 编译器以及编译参数
ASM				=	nasm
ASMFlagOfBoot	=	-I src/boot/include
CC				=	gcc

#==================================================================
# 目标程序以及编译的中间文件
#------------------------------------------------------------------
Typedef = $(tb)/boot.bin $(tb)/loader.bin

#==================================================================
# 所有的伪命令
#------------------------------------------------------------------
.PHONY: nop all image debug run clean realclean
#默认选项 输入:make
nop:
	@echo "all			编译所有文件，生成目标文件(二进制文件，boot.bin)"
	@echo "image		生成系统镜像文件"
	@echo "debug		打开bochs进行系统的运行和调试"
	@echo "run			提示用于如何将系统安装到虚拟机上运行"
	@echo "clean		清理所有的中间编译文件"
	@echo "realclean	完全清理：清理所有的中间编译文件以及生成的目标文件（二进制文件）"

# 编译所有文件
all: $(Typedef)

# 生成系统镜像文件
image: $(os) $(Typedef)
	dd if=$(tb)/boot.bin of=$(os) bs=512 count=1 conv=notrunc
	sudo mount -o loop $(os) $(ImgMountPoint)
	sudo cp -fv $(tb)/loader.bin $(ImgMountPoint)
	sudo umount $(ImgMountPoint)

# 使用bochs进行系统运行和调试
debug:$(os)
	bochs -q


#运行系统，打印提示信息
run:$(os)
	@echo "使用VMware挂载typedef.img软盘即可开始运行"

#清理编译文件
clean:
	@echo ""

#清理所有的中间编译文件以及生成的目标文件
realclean:clean
	-rm -f $(Typedef)
	@echo "已删除全部文件"

#==================================================================
# 目标文件生成规则
#------------------------------------------------------------------
# 软盘文件不存在，生成规则
$(os):
	dd if=/dev/zero of=$(os) bs=512 count=2880

#引导程序生成规则
$(tb)/boot.bin: src/boot/include/fat12hdr.inc
$(tb)/boot.bin: src/boot/boot.asm
	$(ASM) $(ASMFlagOfBoot) -o $@ $<


# 加载程序Loader
$(tb)/loader.bin: src/boot/loader.asm
	$(ASM) $(ASMFlagOfBoot) -o $@ $<


#==================================================================
# 中间OBJ生成规则
#------------------------------------------------------------------





