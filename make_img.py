# Gerar imagem com FAT + dados encadeados
boot = open("loader.bin", "rb").read()

# FAT no setor 2
# Entrada 0 = setor inicial = 3
# Entrada 1: setor 3 → 4
# Entrada 2: setor 4 → 5
# Entrada 3: setor 5 → fim (0xFF)
fat = bytes([3, 4, 5, 0xFF]) + bytes(512 - 4)

# Dados reais: "HELLO, VITOR!\0"
dados = b"HELLO, VITOR!\0"
dados = dados + bytes(512 * 3 - len(dados))  # total de 3 setores

# Montar imagem: boot + fat + dados
img = boot.ljust(512, b'\0') + fat + dados

with open("disk.img", "wb") as f:
    f.write(img)

print("Imagem criada com sucesso!")
