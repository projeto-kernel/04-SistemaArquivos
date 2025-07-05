Compile o loader.asm novamente:

nasm -f bin loader.asm -o loader.bin

Cruze os dedos! Se ele compilar sem erro, você terá um loader.bin de 512 bytes.

Gere a Imagem do Disco:

python create_disk_image.py

Execute no QEMU:

qemu-system-i386 -fda bootable_disk.img -no-shutdown
