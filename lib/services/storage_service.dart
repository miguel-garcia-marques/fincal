import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image/image.dart' as img;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'auth_service.dart';
import '../config/supabase_config.dart';

class StorageService {
  final SupabaseClient _supabase = Supabase.instance.client;
  final AuthService _authService = AuthService();
  final ImagePicker _imagePicker = ImagePicker();
  
  // Nome do bucket no Supabase Storage
  static const String _bucketName = 'profile-pictures';
  
  // Obter o ID do usuário atual
  String? get _currentUserId => _authService.currentUserId;
  
  // Obter o caminho do arquivo no storage baseado no userId
  // Usar timestamp para garantir nome único e evitar conflitos
  String _getFilePath(String userId) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return '$userId/profile_$timestamp.jpg';
  }
  
  // Redimensionar imagem para otimizar tamanho
  Future<Uint8List> _resizeImage(Uint8List imageBytes, {int maxWidth = 400, int maxHeight = 400}) async {
    try {
      final originalImage = img.decodeImage(imageBytes);
      if (originalImage == null) {
        throw Exception('Não foi possível decodificar a imagem');
      }
      
      // Calcular dimensões mantendo proporção
      int width = originalImage.width;
      int height = originalImage.height;
      
      if (width > maxWidth || height > maxHeight) {
        if (width > height) {
          height = (height * maxWidth / width).round();
          width = maxWidth;
        } else {
          width = (width * maxHeight / height).round();
          height = maxHeight;
        }
      }
      
      // Redimensionar imagem
      final resizedImage = img.copyResize(
        originalImage,
        width: width,
        height: height,
      );
      
      // Converter para JPEG com qualidade 85
      return Uint8List.fromList(img.encodeJpg(resizedImage, quality: 85));
    } catch (e) {
      // Se falhar ao redimensionar, retornar imagem original
      return imageBytes;
    }
  }
  
  // Selecionar imagem (funciona em mobile e web)
  Future<Uint8List?> pickImage() async {
    try {
      if (kIsWeb) {
        // Para web, usar file_picker
        final result = await FilePicker.platform.pickFiles(
          type: FileType.image,
          allowMultiple: false,
        );
        
        if (result != null && result.files.single.bytes != null) {
          return result.files.single.bytes;
        }
        return null;
      } else {
        // Para mobile, usar image_picker
        final XFile? pickedFile = await _imagePicker.pickImage(
          source: ImageSource.gallery,
          imageQuality: 85,
        );
        
        if (pickedFile != null) {
          final bytes = await pickedFile.readAsBytes();
          return bytes;
        }
        return null;
      }
    } catch (e) {
      throw Exception('Erro ao selecionar imagem: $e');
    }
  }
  
  // Fazer upload da imagem para o Supabase Storage
  // Se currentProfilePictureUrl for fornecido, deleta a foto antiga antes de fazer upload da nova
  Future<String> uploadProfilePicture(Uint8List imageBytes, {String? currentProfilePictureUrl}) async {
    try {
      print('[StorageService] Iniciando upload da foto de perfil...');
      print('[StorageService] Tamanho da imagem: ${imageBytes.lengthInBytes} bytes');
      
      final userId = _currentUserId;
      print('[StorageService] UserId: $userId');
      if (userId == null) {
        throw Exception('Usuário não autenticado');
      }
      
      // Deletar todas as fotos antigas do usuário antes de fazer upload da nova
      // Isso evita acumulação de arquivos antigos
      try {
        print('[StorageService] Deletando fotos antigas...');
        await _deleteAllUserProfilePictures(userId);
        print('[StorageService] Fotos antigas deletadas');
      } catch (e) {
        print('[StorageService] Aviso: Erro ao deletar fotos antigas (continuando): $e');
        // Continuar mesmo se falhar ao deletar fotos antigas
        // O upload continuará normalmente
      }
      
      // Obter caminho do arquivo (com timestamp único)
      final filePath = _getFilePath(userId);
      print('[StorageService] Caminho do arquivo: $filePath');
      
      // Redimensionar imagem antes de fazer upload
      print('[StorageService] Redimensionando imagem...');
      final resizedImage = await _resizeImage(imageBytes);
      print('[StorageService] Imagem redimensionada. Novo tamanho: ${resizedImage.lengthInBytes} bytes');
      
      // Fazer upload para o Supabase Storage usando HTTP diretamente
      // Isso funciona tanto para web quanto para mobile
      final accessToken = _authService.currentAccessToken;
      print('[StorageService] Token disponível: ${accessToken != null}');
      if (accessToken == null) {
        throw Exception('Token de acesso não disponível');
      }
      
      final supabaseUrl = SupabaseConfig.supabaseUrl;
      final uploadUrl = '$supabaseUrl/storage/v1/object/$_bucketName/$filePath';
      print('[StorageService] URL de upload: $uploadUrl');
      print('[StorageService] Bucket: $_bucketName');
      
      // Fazer upload via HTTP PUT (com upsert para substituir se já existir)
      print('[StorageService] Fazendo upload via HTTP PUT...');
      final response = await http.put(
        Uri.parse(uploadUrl),
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'image/jpeg',
          'x-upsert': 'true',
        },
        body: resizedImage,
      );
      
      print('[StorageService] Resposta do upload: ${response.statusCode}');
      print('[StorageService] Corpo da resposta: ${response.body}');
      
      if (response.statusCode != 200 && response.statusCode != 201) {
        print('[StorageService] ERRO: Status code inválido: ${response.statusCode}');
        print('[StorageService] ERRO: Resposta completa: ${response.body}');
        throw Exception('Erro ao fazer upload: ${response.statusCode} - ${response.body}');
      }
      
      // Obter URL pública da imagem
      final publicUrl = _supabase.storage
          .from(_bucketName)
          .getPublicUrl(filePath);
      
      print('[StorageService] Upload concluído com sucesso!');
      print('[StorageService] URL pública: $publicUrl');
      
      // Verificar se o arquivo realmente existe no storage
      try {
        print('[StorageService] Verificando se arquivo existe no storage...');
        final files = await _supabase.storage
            .from(_bucketName)
            .list(path: userId);
        print('[StorageService] Arquivos encontrados na pasta do usuário: ${files.length}');
        final fileExists = files.any((file) => file.name.contains(filePath.split('/').last));
        print('[StorageService] Arquivo existe no storage: $fileExists');
        if (!fileExists) {
          print('[StorageService] AVISO: Arquivo não encontrado no storage após upload!');
        }
      } catch (verifyError) {
        print('[StorageService] Aviso: Erro ao verificar arquivo no storage: $verifyError');
      }
      
      return publicUrl;
    } catch (e, stackTrace) {
      print('[StorageService] ERRO ao fazer upload da imagem: $e');
      print('[StorageService] Stack trace: $stackTrace');
      throw Exception('Erro ao fazer upload da imagem: $e');
    }
  }
  
  // Deletar todas as fotos de perfil do usuário
  Future<void> _deleteAllUserProfilePictures(String userId) async {
    try {
      // Listar todos os arquivos na pasta do usuário
      final files = await _supabase.storage
          .from(_bucketName)
          .list(path: userId);
      
      if (files.isNotEmpty) {
        // Deletar todos os arquivos encontrados
        final filePaths = files.map((file) => '$userId/${file.name}').toList();
        await _supabase.storage
            .from(_bucketName)
            .remove(filePaths);
      }
    } catch (e) {
      // Ignorar erro se a pasta não existir ou não houver arquivos
      // Isso é normal para usuários sem foto
    }
  }
  
  // Deletar foto de perfil
  Future<void> deleteProfilePicture() async {
    try {
      final userId = _currentUserId;
      if (userId == null) {
        throw Exception('Usuário não autenticado');
      }
      
      // Deletar todas as fotos do usuário
      await _deleteAllUserProfilePictures(userId);
    } catch (e) {
      // Ignorar erro se o arquivo não existir
      if (!e.toString().contains('not found')) {
        throw Exception('Erro ao deletar imagem: $e');
      }
    }
  }
  
  // Obter URL da foto de perfil atual
  String? getProfilePictureUrl(String? profilePictureUrl) {
    if (profilePictureUrl == null || profilePictureUrl.isEmpty) {
      return null;
    }
    return profilePictureUrl;
  }
}

