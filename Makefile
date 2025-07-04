# Arquivos
ASM=loader.asm
BIN=loader.bin
IMG=disk.img
PY=gerar_disco_fat.py

# Build completo
all: $(IMG)

# Compila o bootloader
$(BIN): $(ASM)
	nasm -f bin $(ASM) -o $(BIN)

# Gera a imagem do disco com bootloader, FAT, tabela e clusters
$(IMG): $(BIN) $(PY)
	python $(PY)
	dd if=/dev/zero of=$(IMG) bs=512 count=2880
	dd if=$(BIN) of=$(IMG) bs=512 seek=0 conv=notrunc
	dd if=fat.bin of=$(IMG) bs=512 seek=2 conv=notrunc
	dd if=tabela.bin of=$(IMG) bs=512 seek=3 conv=notrunc
	i=4; \
	for f in clusters/*.bin; do \
	  dd if="$$f" of=$(IMG) bs=512 seek=$$i conv=notrunc; \
	  i=$$((i+1)); \
	done

# Limpa arquivos temporários
clean:
	rm -f *.bin *.img tabela.bin fat.bin
	rm -rf clusters/

# Executa no QEMU
run: all
	qemu-system-x86_64 -drive format=raw,file=$(IMG)
