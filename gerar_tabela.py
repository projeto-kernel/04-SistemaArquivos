# gerar_tabela.py
def escrever_entrada(nome, setor):
    nome = nome.ljust(8)[:8]  # nome com exatamente 8 caracteres
    return nome.encode("ascii") + bytes([setor])

with open("tabela.bin", "wb") as f:
    f.write(escrever_entrada("msg.txt", 2))
    f.write(escrever_entrada("sobre.txt", 3))
    # preenche até 512 bytes
    f.write(b'\x00' * (512 - f.tell()))
