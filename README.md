# Sistema de Inventário (SQL)
Uma solução de backend em SQL voltada para o **controle de estoque e gestão de suprimentos**, focada em precisão e rastreabilidade de dados.
## Funcionalidades do Projeto

- **Catálogo de Produtos:** Organização por categorias e especificações técnicas.
- **Gestão de Fornecedores:** Vinculação de produtos aos seus respectivos distribuidores.
- **Movimentações de Estoque:** Registro detalhado de entradas (compras) e saídas (vendas/perdas).
- **Relatórios de Reposição:** Consultas prontas para identificar itens abaixo do estoque mínimo.

## Status de Desenvolvimento
- [x] Criação do esquema de tabelas (DDL)
- [x] Implementação de chaves estrangeiras e restrições
- [x] Scripts de inserção de dados de teste
- [ ] Criar Procedures para automatizar baixas no estoque
## Exemplo de Consulta (Alerta de Estoque)
O código abaixo demonstra como o sistema identifica produtos que precisam de reposição imediata:
```sql

SELECT nome_produto, quantidade_atual, estoque_minimo
FROM produtos
WHERE quantidade_atual <= estoque_minimo
ORDER BY quantidade_atual ASC;

```
## Dica de Uso
> [!TIP]
> Este modelo pode ser facilmente integrado a sistemas de frente de caixa (PDV) ou painéis de administração de E-commerce para controle de vendas e logística.
## Estrutura das Tabelas
| Tabela | Responsabilidade |
| --- | --- |
| produtos | Informações centrais e saldo atual do item |
| fornecedores | Dados de contato de quem fornece os produtos |
| movimentacoes | Histórico de todas as entradas e saídas |
| categorias | Classificação lógica (ex: Eletrônicos, Alimentos) |
