import struct
import os

# --- Configurações do Disco FAT12 (1.44MB Floppy) ---
TOTAL_SECTORS = 2880           # Total de setores no disquete 1.44MB
SECTORS_PER_FAT = 9            # Setores por Tabela FAT (FAT12)
NUM_FATS = 2                   # Número de FATs (FAT1 e FAT2)
ROOT_DIR_ENTRIES = 224         # Número máximo de entradas no diretório raiz
SECTORS_PER_CLUSTER = 1        # Cada cluster é 1 setor (512 bytes)
BYTES_PER_SECTOR = 512         # Tamanho do setor em bytes
BYTES_PER_DIR_ENTRY = 32       # Tamanho de cada entrada de diretório

# --- Setores Iniciais (LBA) ---
BOOT_SECTOR = 0
FAT1_SECTOR = BOOT_SECTOR + 1
FAT2_SECTOR = FAT1_SECTOR + SECTORS_PER_FAT
ROOT_DIR_SECTOR = FAT2_SECTOR + SECTORS_PER_FAT
# Área de dados começa após o boot, FATs e diretório raiz

# Calcula o número de setores que o diretório raiz ocupa
# Arredonda para cima se não for um múltiplo exato de BYTES_PER_SECTOR
if (ROOT_DIR_ENTRIES * BYTES_PER_DIR_ENTRY) % BYTES_PER_SECTOR != 0:
    ROOT_DIR_SECTORS = (ROOT_DIR_ENTRIES * BYTES_PER_DIR_ENTRY) // BYTES_PER_SECTOR + 1
else:
    ROOT_DIR_SECTORS = (ROOT_DIR_ENTRIES * BYTES_PER_DIR_ENTRY) // BYTES_PER_SECTOR

DATA_START_SECTOR = ROOT_DIR_SECTOR + ROOT_DIR_SECTORS


# --- Validação para o bootloader ---
# Verifique se suas constantes no loader.asm correspondem a estas
print(f"--- FAT12 Disk Layout ---")
print(f"BOOT_SECTOR: {BOOT_SECTOR}")
print(f"FAT1_SECTOR: {FAT1_SECTOR}")
print(f"FAT2_SECTOR: {FAT2_SECTOR}")
print(f"ROOT_DIR_SECTOR: {ROOT_DIR_SECTOR}")
print(f"ROOT_DIR_SECTORS: {ROOT_DIR_SECTORS}") # Isso é importante para o bootloader
print(f"DATA_START_SECTOR (Cluster 2): {DATA_START_SECTOR}")
print(f"-------------------------")

# --- Estruturas FAT12 ---
# Entrada de diretório FAT (32 bytes)
# Offset | Size | Description
# -------|------|------------------------------------
# 0x00   | 8    | Nome do arquivo (ASCII)
# 0x08   | 3    | Extensão do arquivo (ASCII)
# 0x0B   | 1    | Atributos (e.g., 0x01 Read-Only, 0x10 Directory, 0x20 Archive)
# 0x0C   | 10   | Reservado (usado por LFNs)
# 0x16   | 2    | Tempo de criação (não usado aqui)
# 0x18   | 2    | Data de criação (não usado aqui)
# 0x1A   | 2    | Primeiro Cluster (Word)
# 0x1C   | 4    | Tamanho do arquivo em bytes (DWORD)

def create_fat_dir_entry(filename, attributes, first_cluster, file_size):
    # Formatar nome e extensão (8.3)
    name, ext = "", ""
    parts = filename.split('.')
    name = parts[0].ljust(8, ' ')[:8].upper()
    if len(parts) > 1:
        ext = parts[1].ljust(3, ' ')[:3].upper()
    else:
        ext = "   " # Nenhuma extensão

    entry = bytearray(BYTES_PER_DIR_ENTRY)
    entry[0:8] = name.encode('ascii')
    entry[8:11] = ext.encode('ascii')
    entry[0x0B] = attributes
    struct.pack_into('<H', entry, 0x1A, first_cluster) # Primeiro cluster (Little-endian Word)
    struct.pack_into('<I', entry, 0x1C, file_size)     # Tamanho do arquivo (Little-endian Dword)
    return entry

def write_fat_entry(fat_table, cluster_num, value):
    # FAT12 usa 1.5 bytes por entrada.
    # offset_byte é o byte inicial da entrada
    offset_byte = cluster_num + (cluster_num // 2)

    # Descompacta 2 bytes para manipular os 12 bits
    # Pega os 2 bytes que podem conter a entrada do cluster_num
    # e potencialmente a metade da entrada do cluster_num-1 ou cluster_num+1
    # Certifique-se de que o offset não excede o tamanho da tabela fat
    if offset_byte + 1 >= len(fat_table):
        # Isso significa que estamos tentando escrever além dos limites da FAT,
        # o que não deveria acontecer se as configurações e alocações estiverem corretas.
        print(f"Erro: Tentativa de escrever fora dos limites da FAT em cluster {cluster_num}, offset {offset_byte}")
        return

    packed_bytes = struct.unpack_from('<H', fat_table, offset_byte)[0]

    if cluster_num % 2 == 0:  # Cluster par (ex: 0, 2, 4...)
        # Os 12 bits do valor estão nos bits 0-11 dos 2 bytes lidos.
        # Os 4 bits superiores (12-15) dos 2 bytes lidos pertencem ao próximo cluster ímpar.
        # Mantenha os 4 bits superiores, e coloque o 'value' nos 12 bits inferiores.
        packed_bytes = (packed_bytes & 0xF000) | (value & 0x0FFF)
    else:  # Cluster ímpar (ex: 1, 3, 5...)
        # Os 12 bits do valor estão nos bits 4-15 dos 2 bytes lidos.
        # Os 4 bits inferiores (0-3) dos 2 bytes lidos pertencem ao cluster par anterior.
        # Mantenha os 4 bits inferiores, e coloque o 'value' nos 12 bits superiores (shift para a esquerda por 4).
        packed_bytes = (packed_bytes & 0x000F) | ((value & 0x0FFF) << 4)

    # Re-empacota os 2 bytes na tabela FAT
    struct.pack_into('<H', fat_table, offset_byte, packed_bytes)

# --- Criar a Imagem do Disco ---
disk_image = bytearray(TOTAL_SECTORS * BYTES_PER_SECTOR)

# 1. Carregar o Bootloader
try:
    with open("loader.bin", "rb") as f:
        bootloader_code = f.read()
    disk_image[0:len(bootloader_code)] = bootloader_code
    print(f"loader.bin ({len(bootloader_code)} bytes) loaded to boot sector.")
except FileNotFoundError:
    print("Erro: loader.bin não encontrado. Certifique-se de que compilou o bootloader.")
    exit()

# 2. Inicializar as FATs (tabelas de alocação de arquivos)
fat_table_size_bytes = SECTORS_PER_FAT * BYTES_PER_SECTOR
fat1_data = bytearray(fat_table_size_bytes)
fat2_data = bytearray(fat_table_size_bytes)

# Marcar cluster 0 e 1 como reservados na FAT12 (0xFF0, 0xFFF)
# O valor FFF indica End of Cluster Chain
# O valor F0 (primeiros 8 bits de FFF0) é o byte do descritor de mídia para disquete 1.44MB
write_fat_entry(fat1_data, 0, 0xFF0) # Mídia descriptor byte para FAT12 floppy
write_fat_entry(fat1_data, 1, 0xFFF) # End of Chain (EOC) para cluster 1 (reservado)
write_fat_entry(fat2_data, 0, 0xFF0)
write_fat_entry(fat2_data, 1, 0xFFF)


# --- Adicionar arquivos à imagem ---
files_to_add = []

# Exemplo: Adicionar MSG1.TXT
try:
    with open("MSG1.TXT", "rb") as f:
        msg1_content = f.read()
    files_to_add.append({"name": "MSG1.TXT", "content": msg1_content, "attributes": 0x20}) # 0x20 = Archive
    print("MSG1.TXT found.")
except FileNotFoundError:
    print("Aviso: MSG1.TXT não encontrado. Não será adicionado à imagem.")

# Exemplo: Adicionar APP1.BIN
try:
    with open("APP1.BIN", "rb") as f:
        app1_content = f.read()
    files_to_add.append({"name": "APP1.BIN", "content": app1_content, "attributes": 0x20}) # 0x20 = Archive
    print("APP1.BIN found.")
except FileNotFoundError:
    print("Aviso: APP1.BIN não encontrado. Não será adicionado à imagem.")


current_data_cluster = 2 # Clusters FAT12 começam em 2 (0 e 1 são reservados)
root_dir_entry_offset = 0

for f_info in files_to_add:
    file_name = f_info["name"]
    file_content = f_info["content"]
    attributes = f_info["attributes"]
    file_size = len(file_content)

    num_clusters_needed = (file_size + BYTES_PER_SECTOR - 1) // BYTES_PER_SECTOR # Arredonda para cima
    
    # Caso especial para arquivos de tamanho 0: eles não ocupam clusters
    if file_size == 0:
        num_clusters_needed = 0

    if num_clusters_needed == 0: # Arquivo vazio, cluster inicial 0
        first_cluster = 0
    else:
        first_cluster = current_data_cluster # Primeiro cluster para este arquivo
        
        # Alocar clusters na FAT e copiar dados
        for i in range(num_clusters_needed):
            cluster_to_allocate = current_data_cluster + i
            sector_to_write = DATA_START_SECTOR + (cluster_to_allocate - 2) * SECTORS_PER_CLUSTER
            
            # Copiar dados do arquivo para o setor
            start_byte_in_content = i * BYTES_PER_SECTOR
            end_byte_in_content = min((i + 1) * BYTES_PER_SECTOR, file_size)
            
            sector_data = bytearray(BYTES_PER_SECTOR)
            sector_data[0 : end_byte_in_content - start_byte_in_content] = \
                file_content[start_byte_in_content : end_byte_in_content]
            
            disk_image[sector_to_write * BYTES_PER_SECTOR : (sector_to_write + SECTORS_PER_CLUSTER) * BYTES_PER_SECTOR] = sector_data
            
            # Atualizar FAT
            if i < num_clusters_needed - 1:
                # Não é o último cluster, aponta para o próximo
                write_fat_entry(fat1_data, cluster_to_allocate, cluster_to_allocate + 1)
                write_fat_entry(fat2_data, cluster_to_allocate, cluster_to_allocate + 1)
            else:
                # Último cluster da cadeia, marcar como EOC (End Of Chain)
                write_fat_entry(fat1_data, cluster_to_allocate, 0xFFF) # 0xFFF é o EOC para FAT12
                write_fat_entry(fat2_data, cluster_to_allocate, 0xFFF)
        
        current_data_cluster += num_clusters_needed


    # Criar entrada de diretório
    dir_entry = create_fat_dir_entry(file_name, attributes, first_cluster, file_size)
    
    # Adicionar entrada ao diretório raiz
    if root_dir_entry_offset + BYTES_PER_DIR_ENTRY > len(root_dir_data):
        print(f"Erro: Diretório raiz cheio. Não foi possível adicionar {file_name}.")
        continue

    root_dir_data[root_dir_entry_offset : root_dir_entry_offset + BYTES_PER_DIR_ENTRY] = dir_entry
    root_dir_entry_offset += BYTES_PER_DIR_ENTRY
    print(f"Added {file_name} to root directory. First cluster: {first_cluster}, Size: {file_size} bytes.")

# 3. Inicializar o Diretório Raiz (e agora com as entradas de arquivo)
root_dir_start_byte = ROOT_DIR_SECTOR * BYTES_PER_SECTOR
disk_image[root_dir_start_byte : root_dir_start_byte + len(root_dir_data)] = root_dir_data
print("Root directory populated.")


# Atualizar as FATs na imagem com as alocações
disk_image[FAT1_SECTOR * BYTES_PER_SECTOR : (FAT1_SECTOR + SECTORS_PER_FAT) * BYTES_PER_SECTOR] = fat1_data
disk_image[FAT2_SECTOR * BYTES_PER_SECTOR : (FAT2_SECTOR + SECTORS_PER_FAT) * BYTES_PER_SECTOR] = fat2_data
print("FATs updated in disk image.")


# 4. Salvar a Imagem do Disco
output_filename = "bootable_disk.img"
with open(output_filename, "wb") as f:
    f.write(disk_image)

print(f"\nImagem de disquete '{output_filename}' criada com sucesso!")

# Para conveniência, imprima os valores que o bootloader pode precisar
# Verifique se estes valores correspondem às suas definições em loader.asm
print("\n--- Valores para loader.asm (VERIFIQUE!) ---")
print(f"CLUSTER_SIZE equ {BYTES_PER_SECTOR}") # SECTORS_PER_CLUSTER é 1, então cluster_size = BYTES_PER_SECTOR
print(f"FAT_TABLE_SECTOR equ {FAT1_SECTOR}")
print(f"ROOT_DIR_SECTOR equ {ROOT_DIR_SECTOR}")
print(f"ROOT_DIR_SECTORS equ {ROOT_DIR_SECTORS}") # Adicionado para sua referência
print(f"SETOR_DE_DADOS_INICIAL equ {DATA_START_SECTOR}")
print(f"----------------------------------------")