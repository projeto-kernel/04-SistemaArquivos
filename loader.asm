; loader.asm - Nosso Bootloader Simples (Otimizado para 512 bytes)

ORG 0x7C00              ; O bootloader é carregado na memória em 0x7C00
BITS 16                 ; Estamos em modo real de 16 bits

; --- Constantes do Layout do Disco (ATUALIZE SEMPRE COM A SAÍDA DO PYTHON) ---
; Estas constantes são cruciais e devem corresponder exatamente às que o script Python imprime!
CLUSTER_SIZE           equ 512       ; Tamanho de um cluster em bytes (1 setor = 1 cluster)
FAT_TABLE_SECTOR       equ 1         ; Setor de início da FAT1 (no disco, Setor Lógico Absoluto)
ROOT_DIR_SECTOR        equ 19        ; Setor de início do Diretório Raiz (no disco)
SETOR_DE_DADOS_INICIAL equ 33        ; Setor de início da área de dados (onde Cluster 2 começa)

; --- Novas Constantes Necessárias para o Sistema de Arquivos ---
ROOT_DIR_ENTRIES_COUNT equ 224       ; Número máximo de entradas no diretório raiz (para 1.44MB floppy)
ROOT_DIR_SECTORS       equ (ROOT_DIR_ENTRIES_COUNT * 32 + (CLUSTER_SIZE - 1)) / CLUSTER_SIZE ; Setores que o diretório raiz ocupa
MAX_ROOT_ENTRIES       equ ROOT_DIR_ENTRIES_COUNT ; Alias para clareza
BYTES_PER_DIR_ENTRY    equ 32        ; Tamanho de cada entrada de diretório em bytes

; --- Buffer para carregar os arquivos ---
FILE_DATA_BUFFER       equ 0x8000    ; Endereço na memória onde os arquivos serão carregados (8000h)

; --- Atributos de Diretório (para pesquisa) ---
ATTR_LONG_NAME         equ 0x0F      ; Atributo para entradas de nomes longos (ignorar)

; --- Variáveis globais ---
boot_drive             db 0          ; Salva o drive de boot (0x00 ou 0x80)

; --------------------------------------------------------------------------------
; Ponto de entrada do bootloader
; --------------------------------------------------------------------------------
start:
    ; Configura os segmentos de registrador
    xor ax, ax             ; mov ax, 0x0000 (mais curto que mov ax, 0x07C0 e depois mov ax, ax)
    mov ds, ax             ; Segmento de dados para 0x0000 para acesso a IVT/BIOS Data Area
    mov es, ax             ; Segmento extra para 0x0000

    mov ax, 0x07C0
    mov ss, ax             ; Stack em 0x07C0
    mov sp, 0x7C00         ; Stack logo abaixo do bootloader

    ; Salva o número do drive de boot
    mov [boot_drive], dl

    ; Limpa a tela (reduzido)
    mov ah, 0x00
    mov al, 0x03
    int 0x10

    ; Imprime mensagem de inicialização (reduzido)
    mov si, boot_msg
    call print_string

    ; --- TENTATIVA DE CARREGAR MSG1.TXT ---
    ; Para economizar espaço, podemos comentar esta parte
    ; e focar apenas em fazer o bootloader aparecer.
    ; Se você quiser tentar rodar com ela, mantenha.
    ; Se não couber, comente para depois adicionar via "Stage 2".
    
    mov si, msg1_filename   ; Nome do arquivo a procurar
    mov bx, FILE_DATA_BUFFER ; Buffer para carregar o arquivo
    call find_and_load_file ; Procura e carrega o arquivo

    cmp ax, 0               ; Se AX for 0, o arquivo não foi encontrado
    je .no_msg1_found

    mov si, FILE_DATA_BUFFER ; Aponta para o buffer onde MSG1.TXT foi carregado
    call print_string        ; Imprime a string

    jmp .continue_app1_bin

.no_msg1_found:
    mov si, msg1_nf_msg      ; MSG1.TXT não encontrado
    call print_string

.continue_app1_bin:
    ; --- TENTATIVA DE CARREGAR APP1.BIN ---
    mov si, app1_filename   ; Nome do arquivo a procurar
    mov bx, FILE_DATA_BUFFER ; Buffer para carregar o arquivo
    call find_and_load_file ; Procura e carrega o arquivo

    cmp ax, 0               ; Se AX for 0, o arquivo não foi encontrado
    je .no_app1_found

    mov si, app1_exec_msg
    call print_string
    jmp FILE_DATA_BUFFER    ; Pula para o início do código de APP1.BIN

.no_app1_found:
    mov si, app1_nf_msg      ; APP1.BIN não encontrado
    call print_string

; --------------------------------------------------------------------------------
; Loop Infinito (se nada mais for executado)
; --------------------------------------------------------------------------------
hang:
    cli                     ; Desabilita interrupções
    hlt                     ; Para a CPU
    jmp hang                ; Garante que não executa lixo

; --------------------------------------------------------------------------------
; Rotina: print_string (otimizada com loop mais compacto)
; Entrada: SI = endereço da string (DS:SI)
; --------------------------------------------------------------------------------
print_string:
    push ax
    push si
    mov ah, 0x0E            ; Função de "Teletype Output" (INT 10h)
.loop:
    lodsb                   ; Carrega o byte de DS:SI para AL, incrementa SI
    test al, al             ; Testa se AL é zero (mais curto que 'or al, al')
    jz .done                ; Se for zero, fim da string
    int 0x10                ; Imprime o caractere
    jmp .loop
.done:
    pop si
    pop ax
    ret

; --------------------------------------------------------------------------------
; Rotina: read_sectors (nenhuma otimização significativa aqui, é bem otimizada)
; Entrada: AX = setores, BX = buffer (ES:BX), CX = LBA, DL = drive
; Saída: CF set se erro
; --------------------------------------------------------------------------------
read_sectors:
    push ax                 ; Salva AX para preservar o número de setores
    push bx
    push cx
    push dx
    push si                 ; Salva SI pois é usado no CHS calc

    mov cl, al              ; Num setores (AL)
    mov dl, [boot_drive]    ; Drive a ler

    ; LBA para CHS
    mov ax, cx              ; AX = LBA
    xor dx, dx              ; DX = 0
    mov si, 18              ; Setores por trilha
    div si                  ; AX = LBA/18, DX = LBA%18
    mov cl, dl              ; CL = setor (1-18)
    inc cl                  

    mov dh, al              ; AL = LBA/18
    xor dx, dx              ; DX = 0
    mov si, 2               ; Num cabeças
    div si                  ; AX = (LBA/18)/2, DX = (LBA/18)%2
    mov dh, dl              ; DH = cabeça (0 ou 1)

    mov ch, al              ; CH = cilindro

    ; Setup INT 13h
    pop si                  ; Restaura SI
    pop dx                  ; Restaura DX
    pop cx                  ; Restaura CX
    pop bx                  ; Restaura BX
    pop ax                  ; Restaura AX

    mov ah, 0x02            ; Função: Ler Setores
    int 0x13                ; Chama BIOS

    jc .read_error          ; Se CF setado, erro
    clc                     ; Sucesso
    jmp .read_done
.read_error:
    stc                     ; Erro
.read_done:
    ret

; --------------------------------------------------------------------------------
; Rotina: find_and_load_file (foco na otimização de jumps e remoção de redundâncias)
; Entrada: SI = nome do arquivo (DS:SI), BX = buffer de destino (ES:BX)
; Saída: AX = cluster inicial (0 se não encontrado)
; --------------------------------------------------------------------------------
find_and_load_file:
    push si                 ; Salva SI (nome do arquivo a procurar)
    push di                 ; Salva DI
    push bp                 ; Salva BP
    push es                 ; Salva ES
    push cx                 ; Salva CX
    push dx                 ; Salva DX
    push word BX            ; Salva o offset do buffer de destino original (ES:BX)
    push word ES            ; Salva o segmento do buffer de destino original (ES:BX)

    xor ax, ax              ; AX = 0 (assume arquivo não encontrado)
    
    mov ax, FILE_DATA_BUFFER_SEGMENT ; 0x8000 >> 4 = 0x800
    mov es, ax

    mov bx, FILE_DATA_BUFFER ; BX aponta para o início do buffer (ES:BX para read_sectors)
    mov cx, ROOT_DIR_SECTOR ; Setor inicial do diretório raiz
    mov ax, ROOT_DIR_SECTORS ; Número de setores para ler
    call read_sectors       ; Lê os setores do diretório raiz para ES:BX
    jc .error_read_dir_long_jump ; Se erro, pula

    ; SI já tem o nome do arquivo a procurar.
    mov di, FILE_DATA_BUFFER ; DI aponta para o início do diretório lido (primeira entrada)
    mov cx, MAX_ROOT_ENTRIES ; Loop para cada entrada do diretório

.dir_search_loop:
    cmp byte [es:di+0x0B], ATTR_LONG_NAME ; Verifica atributo LFN
    je .next_entry_increment              ; Se for LFN, pula para próxima entrada
    cmp byte [es:di], 0x00               ; Entrada vazia (fim do diretório)
    je .file_not_found_long_jump         ; Se sim, arquivo não encontrado (usa jump longo)
    cmp byte [es:di], 0xE5               ; Entrada deletada
    je .next_entry_increment              ; Se sim, pula para próxima entrada

    call compare_filenames  
    jc .mismatch_long_jump ; Se CF=1, nomes não batem, pula (usa jump longo)
    
    ; Arquivo encontrado!
    mov dx, word [es:di+0x1A] ; DX = Cluster inicial (SALVO AQUI)

    mov ecx, dword [es:di+0x1C] ; ECX = Tamanho do arquivo em bytes
                                
    ; Calcular número de setores para ler (EAX = num_setores)
    xor edx, edx              ; Limpa EDX para a divisão de 32 bits
    mov eax, ecx            ; EAX = Tamanho do arquivo em bytes (32-bit para div)
    mov ebx, CLUSTER_SIZE   ; EBX = Tamanho do cluster (512)
    div ebx                 ; EAX = Quociente (clusters), EDX = Resto
    test edx, edx           ; Se resto > 0, precisa de mais um cluster/setor (mais curto que cmp edx, 0)
    jnz .add_one_sector_file_load_calc
.add_one_sector_file_load_calc:
    inc eax                 ; Adiciona um cluster/setor (se resto > 0 ou sempre, se for 1 setor por cluster)
    ; AX agora contém o número de setores a ler (parte baixa de EAX)

    ; Carregar o arquivo para o buffer de destino original
    pop word es             ; Pop ES do buffer destino
    pop word bx             ; Pop BX do buffer destino
    push word bx            ; Push BX de volta (para o pop do final)
    push word es            ; Push ES de volta (para o pop do final)

    mov cx, dx              ; CX = cluster_inicial (de DX)
    
    ; Converte cluster_inicial para setor físico
    sub cx, 2               ; Ajusta para 0-indexar a partir do Cluster 2
    add cx, SETOR_DE_DADOS_INICIAL ; Adiciona o setor inicial da área de dados
    
    mov dl, [boot_drive]    ; Drive de boot

    call read_sectors
    jc .error_read_file_long_jump ; Se erro, pula

    mov ax, dx              ; Retorna o cluster inicial em AX (de DX)
    jmp .done_find_load_long_jump

.mismatch_long_jump:       ; Alvo do salto longo para nomes que não batem
.next_entry_increment:     ; Alvo do salto longo para LFN/deleted
    add di, BYTES_PER_DIR_ENTRY ; Próxima entrada do diretório (32 bytes)
    loop .dir_search_loop      ; Volta ao início do loop se CX não for zero

    ; Se o loop terminar naturalmente (CX = 0), o arquivo não foi encontrado
.file_not_found_long_jump:
    xor ax, ax              ; AX = 0 (arquivo não encontrado)
    jmp .done_find_load_long_jump

.error_read_dir_long_jump:
.error_read_file_long_jump:
    xor ax, ax              ; AX = 0 (erro)
    stc                     ; Seta Carry Flag para erro
.done_find_load_long_jump:
    pop word ES             ; Restaura o ES original (do buffer de destino)
    pop word BX             ; Restaura o BX original (do buffer de destino)
    pop dx
    pop cx
    pop es                  ; Restaura ES (que foi salvo no início da função)
    pop bp
    pop di
    pop si
    ret

; --------------------------------------------------------------------------------
; Rotina: compare_filenames (otimizada com 'test al, al')
; Entrada: SI = nome, DI = entrada (ES:DI)
; Saída: CF clear=match, CF set=mismatch
; --------------------------------------------------------------------------------
compare_filenames:
    push ax
    push cx
    push dx
    
    mov cx, 11              ; Compara 11 caracteres (8 nome + 3 ext)
    
.compare_loop:
    mov al, byte [si]       ; Carrega char do nome a procurar
    mov bl, byte [es:di]    ; Carrega char da entrada do diretório (usando ES:DI)

    test al, al             ; Fim da string do nome a procurar? (mais curto que 'or al, al')
    jz .fill_with_spaces    ; Se sim, preenche o resto com espaços para comparação
    
    ; Converte para maiúsculas (ambos)
    cmp al, 'a'
    jb .skip_al_up          ; 'jb' é short, ok
    cmp al, 'z'
    ja .skip_al_up          ; 'ja' é short, ok
    sub al, 0x20            ; Para maiúscula
.skip_al_up:

    cmp bl, 'a'
    jb .skip_bl_up          ; 'jb' é short, ok
    cmp bl, 'z'
    ja .skip_bl_up          ; 'ja' é short, ok
    sub bl, 0x20            ; Para maiúscula
.skip_bl_up:

    cmp al, bl              ; Compara os caracteres
    jne .mismatch_cmp       ; Se diferentes, não batem (pode ser short, está dentro da rotina)

    inc si                  ; Próximo caractere no nome a procurar
    inc di                  ; Próximo caractere na entrada do diretório
    loop .compare_loop      ; Loop se CX não for zero
    
    clc                     ; Clear Carry Flag (nomes batem)
    jmp .done_compare_cmp

.fill_with_spaces:
    mov al, ' '             ; Preenche com espaço para comparação (simulando 8.3)
    jmp .skip_bl_up         ; Reusa a lógica de conversão para maiúscula e comparação

.mismatch_cmp:
    stc                     ; Set Carry Flag (nomes não batem)
.done_compare_cmp:
    pop dx
    pop cx
    pop ax
    ret

; --- Mensagens --- (ENCOLHIDAS AO MÁXIMO)
boot_msg                db "Booted!", 0x0D, 0x0A, 0
msg1_filename           db "MSG1.TXT", 0
msg1_nf_msg             db "MSG1 not found.", 0x0D, 0x0A, 0
app1_filename           db "APP1.BIN", 0
app1_nf_msg             db "APP1 not found.", 0x0D, 0x0A, 0
app1_exec_msg           db "Running APP1.", 0x0D, 0x0A, 0

; --- Constante para o segmento do FILE_DATA_BUFFER ---
FILE_DATA_BUFFER_SEGMENT equ FILE_DATA_BUFFER >> 4 ; 0x8000 >> 4 = 0x800

; --- Preenchimento do boot sector ---
; AGORA SIM: FORÇAR PARA 512 BYTES!
times 510 - ($ - $$) db 0   ; Preenche com zeros até o byte 510
dw 0xAA55                   ; Assinatura de boot (bytes 510 e 511)