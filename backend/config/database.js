const mongoose = require('mongoose');
require('dotenv').config();

const connectDB = async () => {
  try {
    // Verificar se MONGODB_URI está definida
    if (!process.env.MONGODB_URI) {
      console.error('❌ ERRO: MONGODB_URI não está definida nas variáveis de ambiente!');
      console.error('Por favor, configure a variável MONGODB_URI no painel do Render com a connection string do MongoDB Atlas.');
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
      console.error('❌ ERRO: A connection string deve começar com "mongodb://" ou "mongodb+srv://"');
      console.error(`URI recebida: ${mongoUri.substring(0, 50)}...`);
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
    
    console.log('🔌 Conectando ao MongoDB...');
    // SEGURANÇA: Não logar URI em produção (mesmo com credenciais ocultas)
    if (process.env.NODE_ENV !== 'production') {
    console.log(`URI: ${mongoUri.replace(/\/\/[^:]+:[^@]+@/, '//***:***@')}`); // Ocultar credenciais no log
    } else {
      console.log('URI: [oculto em produção]');
    }
    
    // Removidas opções deprecated (useNewUrlParser e useUnifiedTopology)
    // Essas opções não são mais necessárias no Mongoose 8.x
    const conn = await mongoose.connect(mongoUri);

    console.log(`✅ MongoDB Connected: ${conn.connection.host}`);
    console.log(`📊 Database: ${conn.connection.name}`);
  } catch (error) {
    console.error('❌ Error connecting to MongoDB:', error.message);
    console.error('Verifique se:');
    console.error('1. A variável MONGODB_URI está configurada no Render');
    console.error('2. A connection string do MongoDB Atlas está correta');
    console.error('3. O IP do Render está permitido no MongoDB Atlas Network Access');
    process.exit(1);
  }
};

module.exports = connectDB;

