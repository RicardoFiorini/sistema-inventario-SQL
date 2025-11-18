-- 1. Configuração Inicial
CREATE DATABASE IF NOT EXISTS SistemaGerenciamentoInventario
CHARACTER SET utf8mb4
COLLATE utf8mb4_0900_ai_ci; -- Collation moderno do MySQL 8

USE SistemaGerenciamentoInventario;

-- 2. Tabelas Auxiliares (Normalização)
CREATE TABLE Categorias (
    categoria_id INT AUTO_INCREMENT PRIMARY KEY,
    nome VARCHAR(100) NOT NULL,
    slug VARCHAR(100) NOT NULL UNIQUE,
    parent_id INT DEFAULT NULL COMMENT 'Para subcategorias (Ex: Eletrônicos > Celulares)',
    FOREIGN KEY (parent_id) REFERENCES Categorias(categoria_id)
);

CREATE TABLE UnidadesMedida (
    unidade_id CHAR(3) PRIMARY KEY, -- UN, KG, LT, CX
    nome VARCHAR(50) NOT NULL
);

CREATE TABLE Armazens (
    armazem_id INT AUTO_INCREMENT PRIMARY KEY,
    nome VARCHAR(100) NOT NULL,
    localizacao VARCHAR(200),
    ativo BOOLEAN DEFAULT TRUE
);

-- 3. Tabela de Produtos (Mestre)
CREATE TABLE Produtos (
    produto_id INT AUTO_INCREMENT PRIMARY KEY,
    sku VARCHAR(50) NOT NULL UNIQUE COMMENT 'Código único universal (Stock Keeping Unit)',
    codigo_barras VARCHAR(100) UNIQUE,
    nome VARCHAR(150) NOT NULL,
    categoria_id INT NOT NULL,
    unidade_id CHAR(3) NOT NULL DEFAULT 'UN',
    
    -- Gestão de Custos e Preços
    preco_custo_medio DECIMAL(12, 4) DEFAULT 0.0000 COMMENT 'Calculado automaticamente',
    preco_venda DECIMAL(12, 2) NOT NULL,
    margem_lucro DECIMAL(5, 2) GENERATED ALWAYS AS (((preco_venda - preco_custo_medio) / preco_venda) * 100) STORED,
    
    -- Controle de Níveis
    estoque_minimo INT DEFAULT 10,
    estoque_maximo INT DEFAULT 100,
    
    ativo BOOLEAN DEFAULT TRUE,
    criado_em DATETIME DEFAULT CURRENT_TIMESTAMP,
    
    FOREIGN KEY (categoria_id) REFERENCES Categorias(categoria_id),
    FOREIGN KEY (unidade_id) REFERENCES UnidadesMedida(unidade_id),
    
    INDEX idx_busca_produto (nome, sku, codigo_barras)
);

-- 4. Tabela de Estoque Localizado (Saldo por Armazém)
-- O produto pode ter 10 unidades no Loja A e 50 no Depósito Central
CREATE TABLE EstoqueSaldo (
    produto_id INT NOT NULL,
    armazem_id INT NOT NULL,
    quantidade_atual DECIMAL(12, 3) DEFAULT 0,
    localizacao_fisica VARCHAR(50) COMMENT 'Corredor A, Prateleira 2',
    ultima_movimentacao DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    
    PRIMARY KEY (produto_id, armazem_id),
    FOREIGN KEY (produto_id) REFERENCES Produtos(produto_id),
    FOREIGN KEY (armazem_id) REFERENCES Armazens(armazem_id)
);

-- 5. Tabela de Movimentações (O Livro Razão / Ledger)
-- NUNCA faça Updates aqui. Apenas Inserts.
CREATE TABLE Movimentacoes (
    movimentacao_id BIGINT AUTO_INCREMENT PRIMARY KEY,
    produto_id INT NOT NULL,
    armazem_id INT NOT NULL,
    tipo ENUM('Compra', 'Venda', 'Transferencia_Entrada', 'Transferencia_Saida', 'Ajuste_Perda', 'Ajuste_Sobra') NOT NULL,
    
    quantidade DECIMAL(12, 3) NOT NULL, -- Pode vender 1.5 KG
    custo_unitario DECIMAL(12, 4) NOT NULL COMMENT 'O custo no momento da operação',
    valor_total DECIMAL(12, 2) GENERATED ALWAYS AS (quantidade * custo_unitario) STORED,
    
    documento_ref VARCHAR(50) COMMENT 'Número da Nota Fiscal ou Pedido',
    observacao TEXT,
    usuario_responsavel VARCHAR(100) NOT NULL, -- Em prod, seria um ID de usuário
    data_movimentacao DATETIME DEFAULT CURRENT_TIMESTAMP,
    
    FOREIGN KEY (produto_id) REFERENCES Produtos(produto_id),
    FOREIGN KEY (armazem_id) REFERENCES Armazens(armazem_id),
    
    INDEX idx_historico (produto_id, data_movimentacao DESC)
);

-- =========================================================
-- 🧠 LÓGICA DE INTEGRIDADE E CÁLCULO (CORE DO WMS)
-- =========================================================

-- VIEW: Relatório de Reposição (O que precisa comprar?)
CREATE OR REPLACE VIEW v_RelatorioReposicao AS
SELECT 
    p.sku,
    p.nome,
    u.unidade_id,
    SUM(e.quantidade_atual) AS saldo_total,
    p.estoque_minimo,
    (p.estoque_maximo - SUM(e.quantidade_atual)) AS sugestao_compra
FROM Produtos p
JOIN EstoqueSaldo e ON p.produto_id = e.produto_id
GROUP BY p.produto_id
HAVING saldo_total <= p.estoque_minimo;

-- PROCEDURE: Registrar Movimentação (A única forma de mexer no estoque)
-- Encapsula: Validação + Insert no Histórico + Update no Saldo + Recálculo de Custo Médio
DELIMITER //
CREATE PROCEDURE sp_RegistrarMovimento(
    IN p_produto_id INT,
    IN p_armazem_id INT,
    IN p_tipo VARCHAR(20),
    IN p_quantidade DECIMAL(12,3),
    IN p_custo DECIMAL(12,4), -- Se for venda, passa NULL (usa custo médio)
    IN p_doc_ref VARCHAR(50),
    IN p_usuario VARCHAR(100)
)
BEGIN
    DECLARE v_saldo_atual DECIMAL(12,3) DEFAULT 0;
    DECLARE v_custo_atual DECIMAL(12,4);
    DECLARE v_novo_custo DECIMAL(12,4);
    
    -- Iniciar Transação (Tudo ou Nada)
    START TRANSACTION;
    
    -- 1. Bloqueia a linha do saldo para evitar condição de corrida (Row Locking)
    SELECT quantidade_atual INTO v_saldo_atual 
    FROM EstoqueSaldo 
    WHERE produto_id = p_produto_id AND armazem_id = p_armazem_id 
    FOR UPDATE;
    
    -- Se não existe registro de saldo neste armazém, cria com 0
    IF v_saldo_atual IS NULL THEN
        INSERT INTO EstoqueSaldo (produto_id, armazem_id, quantidade_atual) VALUES (p_produto_id, p_armazem_id, 0);
        SET v_saldo_atual = 0;
    END IF;

    -- 2. Busca Custo Médio Atual
    SELECT preco_custo_medio INTO v_custo_atual FROM Produtos WHERE produto_id = p_produto_id;

    -- 3. Lógica de Entrada vs Saída
    IF p_tipo IN ('Compra', 'Transferencia_Entrada', 'Ajuste_Sobra') THEN
        -- Recalcula Custo Médio (Média Ponderada) na Entrada de Compra
        IF p_tipo = 'Compra' THEN
             -- ( (QtdAtual * CustoAtual) + (QtdNova * CustoNovo) ) / (QtdAtual + QtdNova)
            SET v_novo_custo = ((v_saldo_atual * v_custo_atual) + (p_quantidade * p_custo)) / (v_saldo_atual + p_quantidade);
            UPDATE Produtos SET preco_custo_medio = v_novo_custo WHERE produto_id = p_produto_id;
        ELSE
            SET p_custo = v_custo_atual; -- Outras entradas mantêm o custo
        END IF;

        -- Atualiza Saldo
        UPDATE EstoqueSaldo SET quantidade_atual = quantidade_atual + p_quantidade 
        WHERE produto_id = p_produto_id AND armazem_id = p_armazem_id;

    ELSEIF p_tipo IN ('Venda', 'Transferencia_Saida', 'Ajuste_Perda') THEN
        -- Valida Estoque Negativo
        IF v_saldo_atual < p_quantidade THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERRO: Estoque insuficiente neste armazém.';
        END IF;

        SET p_custo = v_custo_atual; -- Saída usa o custo médio atual

        -- Atualiza Saldo
        UPDATE EstoqueSaldo SET quantidade_atual = quantidade_atual - p_quantidade 
        WHERE produto_id = p_produto_id AND armazem_id = p_armazem_id;
    END IF;

    -- 4. Insere no Histórico (Log Imutável)
    INSERT INTO Movimentacoes (produto_id, armazem_id, tipo, quantidade, custo_unitario, documento_ref, usuario_responsavel)
    VALUES (p_produto_id, p_armazem_id, p_tipo, p_quantidade, p_custo, p_doc_ref, p_usuario);

    COMMIT;
END //
DELIMITER ;

-- TRIGGER: Auditoria de Segurança (Impede Update/Delete no Histórico)
DELIMITER //
CREATE TRIGGER trg_ProtegerMovimentacoes_Del
BEFORE DELETE ON Movimentacoes
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'PROIBIDO: Movimentações fiscais não podem ser deletadas. Faça um estorno.';
END //

CREATE TRIGGER trg_ProtegerMovimentacoes_Upd
BEFORE UPDATE ON Movimentacoes
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'PROIBIDO: O histórico de estoque é imutável.';
END //
DELIMITER ;
