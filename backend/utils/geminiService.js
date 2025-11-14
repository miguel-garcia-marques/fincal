const https = require('https');

/**
 * Processa uma imagem de fatura usando a API Gemini do Firebase AI Logic
 * @param {string} imageBase64 - Imagem em base64
 * @returns {Promise<Object>} - Dados extraídos da fatura
 */
async function processInvoiceImage(imageBase64) {
  const apiKey = process.env.GEMINI_API_KEY;
  
  if (!apiKey) {
    throw new Error('GEMINI_API_KEY não configurada nas variáveis de ambiente');
  }

  // Remover o prefixo data:image/...;base64, se existir
  const base64Data = imageBase64.replace(/^data:image\/[a-z]+;base64,/, '');

  // Prompt para extrair informações da fatura
  const prompt = `Analise esta imagem de uma fatura/recibo e extraia as seguintes informações em formato JSON:

1. **valor** (number): O valor total da fatura em euros. Se encontrar múltiplos valores, use o valor total final.
2. **categoria** (string): Categoria da transação baseada no tipo de estabelecimento/produto. Use uma das seguintes categorias:
   - "compras" - supermercado, loja de conveniência
   - "cafe" - café, pastelaria
   - "combustivel" - posto de gasolina
   - "subscricao" - serviços de assinatura
   - "saude" - farmácia, clínica
   - "comerFora" - restaurante, fast food
   - "comprasOnline" - compras online
   - "comprasRoupa" - loja de roupas
   - "comunicacoes" - telefone, internet
   - "miscelaneos" - outros
3. **descricao** (string): Uma descrição curta e clara da transação baseada no estabelecimento ou produtos principais
4. **estabelecimento** (string, opcional): Nome do estabelecimento se visível
5. **data** (string, opcional): Data da fatura no formato YYYY-MM-DD se visível

Retorne APENAS um objeto JSON válido, sem markdown, sem explicações adicionais. Exemplo:
{
  "valor": 45.50,
  "categoria": "compras",
  "descricao": "Compras no supermercado",
  "estabelecimento": "Continente",
  "data": "2025-01-15"
}`;

  const requestBody = {
    contents: [
      {
        parts: [
          {
            text: prompt
          },
          {
            inline_data: {
              mime_type: "image/jpeg",
              data: base64Data
            }
          }
        ]
      }
    ]
  };

  return new Promise((resolve, reject) => {
    const options = {
      hostname: 'generativelanguage.googleapis.com',
      path: `/v1beta/models/gemini-1.5-flash:generateContent?key=${apiKey}`,
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
    };

    const req = https.request(options, (res) => {
      let data = '';

      res.on('data', (chunk) => {
        data += chunk;
      });

      res.on('end', () => {
        try {
          if (res.statusCode !== 200) {
            const errorData = JSON.parse(data);
            reject(new Error(`Erro na API Gemini: ${errorData.error?.message || 'Erro desconhecido'}`));
            return;
          }

          const response = JSON.parse(data);
          
          // Extrair o texto da resposta
          const text = response.candidates?.[0]?.content?.parts?.[0]?.text;
          
          if (!text) {
            reject(new Error('Resposta da API Gemini não contém texto'));
            return;
          }

          // Tentar extrair JSON da resposta (pode vir com markdown ou texto adicional)
          let jsonText = text.trim();
          
          // Remover markdown code blocks se existirem
          jsonText = jsonText.replace(/```json\n?/g, '').replace(/```\n?/g, '');
          
          // Tentar encontrar o JSON no texto
          const jsonMatch = jsonText.match(/\{[\s\S]*\}/);
          if (jsonMatch) {
            jsonText = jsonMatch[0];
          }

          const extractedData = JSON.parse(jsonText);
          
          // Validar e normalizar os dados
          const normalizedData = {
            amount: extractedData.valor || extractedData.amount || 0,
            category: _mapCategory(extractedData.categoria || extractedData.category),
            description: extractedData.descricao || extractedData.description || 'Transação',
            establishment: extractedData.estabelecimento || extractedData.establishment || null,
            date: extractedData.data || extractedData.date || null,
          };

          resolve(normalizedData);
        } catch (error) {
          console.error('Erro ao processar resposta do Gemini:', error);
          console.error('Resposta recebida:', data);
          reject(new Error(`Erro ao processar resposta: ${error.message}`));
        }
      });
    });

    req.on('error', (error) => {
      reject(new Error(`Erro na requisição: ${error.message}`));
    });

    req.write(JSON.stringify(requestBody));
    req.end();
  });
}

/**
 * Mapeia a categoria extraída para uma categoria válida do sistema
 */
function _mapCategory(category) {
  if (!category) return 'miscelaneos';
  
  const categoryLower = category.toLowerCase();
  
  const categoryMap = {
    'compras': 'compras',
    'supermercado': 'compras',
    'cafe': 'cafe',
    'pastelaria': 'cafe',
    'combustivel': 'combustivel',
    'gasolina': 'combustivel',
    'subscricao': 'subscricao',
    'assinatura': 'subscricao',
    'saude': 'saude',
    'farmacia': 'saude',
    'comerfora': 'comerFora',
    'restaurante': 'comerFora',
    'fastfood': 'comerFora',
    'comprasonline': 'comprasOnline',
    'online': 'comprasOnline',
    'comprasroupa': 'comprasRoupa',
    'roupa': 'comprasRoupa',
    'comunicacoes': 'comunicacoes',
    'telefone': 'comunicacoes',
    'internet': 'comunicacoes',
  };

  return categoryMap[categoryLower] || 'miscelaneos';
}

module.exports = {
  processInvoiceImage
};

