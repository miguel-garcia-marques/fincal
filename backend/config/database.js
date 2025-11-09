const mongoose = require('mongoose');
require('dotenv').config();

const connectDB = async () => {
  try {
    let mongoUri = process.env.MONGODB_URI || 'mongodb://localhost:27017/fincal';
    
    // Se a URI não especificar uma database, adicionar 'fincal'
    // Padrão: mongodb://host:port/database
    if (!mongoUri.match(/\/[^\/\?]+(\?|$)/)) {
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
  } catch (error) {
    console.error('Error connecting to MongoDB:', error.message);
    process.exit(1);
  }
};

module.exports = connectDB;

