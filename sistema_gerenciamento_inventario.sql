-- Criação do banco de dados
CREATE DATABASE SistemaGerenciamentoInventario;
USE SistemaGerenciamentoInventario;

-- Tabela para armazenar categorias de produtos
CREATE TABLE Categorias (
    categoria_id INT AUTO_INCREMENT PRIMARY KEY,
    nome VARCHAR(100) NOT NULL UNIQUE,
    descricao TEXT
);

-- Tabela para armazenar fornecedores
CREATE TABLE Fornecedores (
    fornecedor_id INT AUTO_INCREMENT PRIMARY KEY,
    nome VARCHAR(100) NOT NULL UNIQUE,
    contato VARCHAR(100),
    telefone VARCHAR(20),
    email VARCHAR(100) UNIQUE,
    data_registro DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- Tabela para armazenar produtos
CREATE TABLE Produtos (
    produto_id INT AUTO_INCREMENT PRIMARY KEY,
    nome VARCHAR(100) NOT NULL,
    categoria_id INT NOT NULL,
    fornecedor_id INT NOT NULL,
    preco DECIMAL(10, 2) NOT NULL,
    quantidade INT NOT NULL DEFAULT 0,
    data_cadastro DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (categoria_id) REFERENCES Categorias(categoria_id) ON DELETE CASCADE,
    FOREIGN KEY (fornecedor_id) REFERENCES Fornecedores(fornecedor_id) ON DELETE CASCADE
);

-- Tabela para armazenar movimentações de estoque
CREATE TABLE Movimentacoes (
    movimentacao_id INT AUTO_INCREMENT PRIMARY KEY,
    produto_id INT NOT NULL,
    quantidade INT NOT NULL,
    tipo ENUM('Entrada', 'Saída') NOT NULL,
    data_movimentacao DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (produto_id) REFERENCES Produtos(produto_id) ON DELETE CASCADE
);

-- Índices para melhorar a performance
CREATE INDEX idx_produto_nome ON Produtos(nome);
CREATE INDEX idx_categoria_nome ON Categorias(nome);
CREATE INDEX idx_fornecedor_nome ON Fornecedores(nome);
CREATE INDEX idx_movimentacao_produto ON Movimentacoes(produto_id);
CREATE INDEX idx_movimentacao_tipo ON Movimentacoes(tipo);

-- View para listar produtos com informações detalhadas
CREATE VIEW ViewProdutos AS
SELECT p.produto_id, p.nome AS produto, c.nome AS categoria, 
       f.nome AS fornecedor, p.preco, p.quantidade, p.data_cadastro
FROM Produtos p
JOIN Categorias c ON p.categoria_id = c.categoria_id
JOIN Fornecedores f ON p.fornecedor_id = f.fornecedor_id
ORDER BY p.nome;

-- Função para obter a quantidade total de produtos em estoque
DELIMITER //
CREATE FUNCTION QuantidadeTotalEmEstoque(produtoId INT) RETURNS INT
BEGIN
    DECLARE qtd INT;
    SELECT quantidade INTO qtd FROM Produtos WHERE produto_id = produtoId;
    RETURN qtd;
END //
DELIMITER ;

-- Função para calcular o valor total em estoque de um produto
DELIMITER //
CREATE FUNCTION ValorTotalEmEstoque(produtoId INT) RETURNS DECIMAL(10, 2)
BEGIN
    DECLARE valor DECIMAL(10, 2);
    SELECT quantidade * preco INTO valor 
    FROM Produtos WHERE produto_id = produtoId;
    RETURN IFNULL(valor, 0);
END //
DELIMITER ;

-- Trigger para atualizar a quantidade de produtos após uma movimentação de estoque
DELIMITER //
CREATE TRIGGER Trigger_AntesMovimentacao
BEFORE INSERT ON Movimentacoes
FOR EACH ROW
BEGIN
    DECLARE estoqueAtual INT;
    SELECT quantidade INTO estoqueAtual FROM Produtos WHERE produto_id = NEW.produto_id;
    
    IF NEW.tipo = 'Saída' AND estoqueAtual < NEW.quantidade THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Estoque insuficiente para a saída.';
    END IF;
END //
DELIMITER ;

-- Trigger para atualizar a quantidade do produto após a movimentação
DELIMITER //
CREATE TRIGGER Trigger_AposMovimentacao
AFTER INSERT ON Movimentacoes
FOR EACH ROW
BEGIN
    IF NEW.tipo = 'Entrada' THEN
        UPDATE Produtos SET quantidade = quantidade + NEW.quantidade 
        WHERE produto_id = NEW.produto_id;
    ELSEIF NEW.tipo = 'Saída' THEN
        UPDATE Produtos SET quantidade = quantidade - NEW.quantidade 
        WHERE produto_id = NEW.produto_id;
    END IF;
END //
DELIMITER ;

-- Inserção de exemplo de categorias
INSERT INTO Categorias (nome, descricao) VALUES 
('Eletrônicos', 'Dispositivos eletrônicos e acessórios.'),
('Móveis', 'Móveis para casa e escritório.'),
('Vestuário', 'Roupas e acessórios.');

-- Inserção de exemplo de fornecedores
INSERT INTO Fornecedores (nome, contato, telefone, email) VALUES 
('Fornecedor A', 'João', '123456789', 'fornecedorA@example.com'),
('Fornecedor B', 'Maria', '987654321', 'fornecedorB@example.com');

-- Inserção de exemplo de produtos
INSERT INTO Produtos (nome, categoria_id, fornecedor_id, preco, quantidade) VALUES 
('Smartphone', 1, 1, 1200.00, 50),
('Notebook', 1, 1, 3500.00, 30),
('Cadeira', 2, 2, 800.00, 20),
('Camisa', 3, 2, 120.00, 100);

-- Inserção de exemplo de movimentações de estoque
INSERT INTO Movimentacoes (produto_id, quantidade, tipo) VALUES 
(1, 10, 'Entrada'),
(2, 5, 'Saída'),
(3, 3, 'Entrada'),
(1, 2, 'Saída');

-- Selecionar todos os produtos
SELECT * FROM ViewProdutos;

-- Obter quantidade total em estoque de um produto específico
SELECT QuantidadeTotalEmEstoque(1) AS quantidade_produto_1;

-- Calcular valor total em estoque de um produto específico
SELECT ValorTotalEmEstoque(1) AS valor_total_produto_1;

-- Excluir uma movimentação
DELETE FROM Movimentacoes WHERE movimentacao_id = 1;

-- Excluir um produto (isso falhará se o produto tiver movimentações)
DELETE FROM Produtos WHERE produto_id = 1;
