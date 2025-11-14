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

  // Modelos baseados na lista de disponíveis do usuário
  // Ordem: tentar modelos gratuitos primeiro, com retry para "overloaded"
  const modelsToTry = [
    { name: 'gemini-2.5-flash', version: 'v1beta', retryOnOverload: true }, // Disponível mas pode estar overloaded
    { name: 'gemini-2.0-flash', version: 'v1beta' }, // Versão estável que pode estar no tier gratuito
    { name: 'gemini-2.0-flash-001', version: 'v1beta' }, // Versão específica
    { name: 'gemini-flash-latest', version: 'v1beta' }, // Alias para modelo mais recente
    { name: 'gemini-2.5-flash-lite', version: 'v1beta' }, // Versão lite (mais leve, pode ser gratuita)
  ];

  // Função auxiliar para listar modelos disponíveis (para debug)
  const listAvailableModels = () => {
    return new Promise((resolve, reject) => {
      const options = {
        hostname: 'generativelanguage.googleapis.com',
        path: `/v1beta/models?key=${apiKey}`,
        method: 'GET',
        headers: {
          'Content-Type': 'application/json',
        },
      };

      const req = https.request(options, (res) => {
        let data = '';
        res.on('data', (chunk) => { data += chunk; });
        res.on('end', () => {
          if (res.statusCode === 200) {
            try {
              const response = JSON.parse(data);
              resolve(response.models || []);
            } catch (e) {
              reject(e);
            }
          } else {
            reject(new Error(`Erro ao listar modelos: ${res.statusCode}`));
          }
        });
      });

      req.on('error', reject);
      req.end();
    });
  };

  // Função para tentar fazer a requisição com um modelo específico (com retry para overload)
  const tryModel = (modelConfig, retryCount = 0) => {
    return new Promise((resolve, reject) => {
      const options = {
        hostname: 'generativelanguage.googleapis.com',
        path: `/${modelConfig.version}/models/${modelConfig.name}:generateContent?key=${apiKey}`,
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
          if (res.statusCode !== 200) {
            try {
              const errorData = JSON.parse(data);
              const errorMessage = errorData.error?.message || 'Erro desconhecido';
              
              // Se estiver overloaded e tiver retry configurado, tentar novamente após delay
              if (errorMessage.includes('overloaded') && modelConfig.retryOnOverload && retryCount < 2) {
                const delay = (retryCount + 1) * 2000; // 2s, 4s
                console.log(`⏳ Modelo ${modelConfig.name} sobrecarregado, tentando novamente em ${delay}ms...`);
                setTimeout(() => {
                  tryModel(modelConfig, retryCount + 1).then(resolve).catch(reject);
                }, delay);
                return;
              }
              
              // Se excedeu quota gratuita (limit: 0), não tentar novamente
              if (errorMessage.includes('limit: 0') || errorMessage.includes('quota')) {
                reject(new Error(`Modelo ${modelConfig.name}: Sem quota gratuita disponível - ${errorMessage}`));
                return;
              }
              
              reject(new Error(`Modelo ${modelConfig.name}: ${errorMessage}`));
            } catch (parseError) {
              reject(new Error(`Modelo ${modelConfig.name}: Erro ao processar resposta (${res.statusCode})`));
            }
            return;
          }

          try {
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
  };

  // Primeiro, tentar listar modelos disponíveis (opcional, para debug)
  let availableModels = [];
  try {
    availableModels = await listAvailableModels();
    console.log('📋 Modelos disponíveis:', availableModels.map(m => m.name).join(', '));
  } catch (error) {
    console.log('⚠️ Não foi possível listar modelos disponíveis, continuando com tentativas...');
  }

  // Tentar cada modelo até que um funcione
  let lastError = null;
  const errors = [];
  
  for (const modelConfig of modelsToTry) {
    try {
      const result = await tryModel(modelConfig);
      console.log(`✅ Modelo ${modelConfig.name} (${modelConfig.version}) funcionou com sucesso!`);
      return result;
    } catch (error) {
      lastError = error;
      const errorMsg = `Modelo ${modelConfig.name} (${modelConfig.version}): ${error.message}`;
      errors.push(errorMsg);
      console.log(`❌ ${errorMsg}`);
      continue;
    }
  }

  // Se nenhum modelo funcionou, lançar erro com todos os detalhes
  const allErrors = errors.join('\n');
  let errorMessage = `Todos os modelos gratuitos falharam. Verifique se sua API key está correta e se tem acesso aos modelos gratuitos.\n\nErros:\n${allErrors}\n\n`;
  
  if (availableModels.length > 0) {
    const modelNames = availableModels.map(m => m.name).join(', ');
    errorMessage += `📋 Modelos disponíveis na sua conta: ${modelNames}\n\n`;
  }
  
  errorMessage += `Certifique-se de que:\n` +
    `1. A GEMINI_API_KEY está configurada corretamente\n` +
    `2. Você está usando uma conta com acesso ao tier gratuito\n` +
    `3. Os modelos estão disponíveis na sua região\n` +
    `4. Verifique os logs do servidor para ver quais modelos foram tentados`;
  
  throw new Error(errorMessage);
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

