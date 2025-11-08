const mongoose = require('mongoose');
require('dotenv').config();

const connectDB = async () => {
  try {
    // Garantir que estamos usando a database 'fincal' e não 'test'
    let mongoUri = process.env.MONGODB_URI || 'mongodb://localhost:27017/fincal';
    
    // Se a URI não especificar uma database ou usar 'test', substituir por 'fincal'
    // Padrão: mongodb://host:port/database
    if (mongoUri.includes('/test') || mongoUri.includes('/test?')) {
      mongoUri = mongoUri.replace('/test', '/fincal');
    } else if (!mongoUri.match(/\/[^\/\?]+(\?|$)/)) {
      // Se não tem database especificada, adicionar 'fincal'
      mongoUri = mongoUri.endsWith('/') 
        ? mongoUri + 'fincal'
        : mongoUri + '/fincal';
    }
    
    const conn = await mongoose.connect(mongoUri, {
      useNewUrlParser: true,
      useUnifiedTopology: true,
    });

    console.log(`MongoDB Connected: ${conn.connection.host}`);
    console.log(`Database: ${conn.connection.name}`);
    
    // Verificar se não está usando 'test'
    if (conn.connection.name === 'test') {
      console.warn('⚠️  WARNING: Connected to "test" database. Please update MONGODB_URI to use "fincal" database.');
    }
  } catch (error) {
    console.error('Error connecting to MongoDB:', error.message);
    process.exit(1);
  }
};

module.exports = connectDB;

