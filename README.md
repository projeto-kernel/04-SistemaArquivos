💻 Como testar
Compile com NASM:

nasm -f bin -o loader.bin loader.asm

Rode o script Python:

python make_img.py

Execute com QEMU:

qemu-system-x86_64 -fda disk.img

Você verá:

Carregando via FAT...
HELLO, VITOR!