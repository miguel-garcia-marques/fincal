const mongoose = require('mongoose');
require('dotenv').config();

const connectDB = async () => {
  try {
    // Verificar se MONGODB_URI está definida
    if (!process.env.MONGODB_URI) {
      process.exit(1);
    }

    let mongoUri = process.env.MONGODB_URI;
    
    // Remover qualquer prefixo "MONGODB_URI=" que possa ter sido incluído por engano
    // Isso pode acontecer se o usuário copiou a variável com o nome no Render
    mongoUri = mongoUri.replace(/^MONGODB_URI\s*=\s*/i, '');
    
    // Remover espaços em branco no início e fim
    mongoUri = mongoUri.trim();
    
    // Remover parâmetros desnecessários que podem causar problemas
    // O appName não é necessário e pode causar problemas de conexão
    mongoUri = mongoUri.replace(/\?appName=[^&]*/, '');
    mongoUri = mongoUri.replace(/\?$/, ''); // Remover ? no final se houver
    
    // Validar que a URI começa com mongodb:// ou mongodb+srv://
    if (!mongoUri.match(/^mongodb(\+srv)?:\/\//)) {
      process.exit(1);
    }
    
    // Se a URI não especificar uma database, adicionar 'fincal'
    // Padrão: mongodb://host:port/database ou mongodb+srv://host/database
    if (!mongoUri.match(/\/[^\/\?]+(\?|$)/)) {
      // Se não tem database especificada, adicionar 'fincal'
      mongoUri = mongoUri.endsWith('/') 
        ? mongoUri + 'fincal'
        : mongoUri + '/fincal';
    }
    
    // Removidas opções deprecated (useNewUrlParser e useUnifiedTopology)
    // Essas opções não são mais necessárias no Mongoose 8.x
    const conn = await mongoose.connect(mongoUri);
  } catch (error) {
    process.exit(1);
  }
};

module.exports = connectDB;
