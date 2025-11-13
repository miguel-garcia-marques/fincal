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
  String _getFilePath(String userId) {
    return '$userId/profile.jpg';
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
      final userId = _currentUserId;
      if (userId == null) {
        throw Exception('Usuário não autenticado');
      }
      
      // Obter caminho do arquivo
      final filePath = _getFilePath(userId);
      
      // Se houver uma foto antiga, deletá-la antes de fazer upload da nova
      if (currentProfilePictureUrl != null && currentProfilePictureUrl.isNotEmpty) {
        try {
          // Verificar se a foto antiga está no mesmo bucket e caminho esperado
          // Se estiver, deletar antes de fazer upload da nova
          await deleteProfilePicture();
        } catch (e) {
          // Se falhar ao deletar, continuar mesmo assim (pode ser que a foto não exista mais)
          // O upsert vai substituir o arquivo de qualquer forma
        }
      }
      
      // Redimensionar imagem antes de fazer upload
      final resizedImage = await _resizeImage(imageBytes);
      
      // Fazer upload para o Supabase Storage usando HTTP diretamente
      // Isso funciona tanto para web quanto para mobile
      final accessToken = _authService.currentAccessToken;
      if (accessToken == null) {
        throw Exception('Token de acesso não disponível');
      }
      
      final supabaseUrl = SupabaseConfig.supabaseUrl;
      final uploadUrl = '$supabaseUrl/storage/v1/object/$_bucketName/$filePath';
      
      // Fazer upload via HTTP PUT (com upsert para substituir se já existir)
      final response = await http.put(
        Uri.parse(uploadUrl),
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'image/jpeg',
          'x-upsert': 'true',
        },
        body: resizedImage,
      );
      
      if (response.statusCode != 200 && response.statusCode != 201) {
        throw Exception('Erro ao fazer upload: ${response.statusCode} - ${response.body}');
      }
      
      // Obter URL pública da imagem
      final publicUrl = _supabase.storage
          .from(_bucketName)
          .getPublicUrl(filePath);
      
      return publicUrl;
    } catch (e) {
      throw Exception('Erro ao fazer upload da imagem: $e');
    }
  }
  
  // Deletar foto de perfil
  Future<void> deleteProfilePicture() async {
    try {
      final userId = _currentUserId;
      if (userId == null) {
        throw Exception('Usuário não autenticado');
      }
      
      final filePath = _getFilePath(userId);
      
      await _supabase.storage
          .from(_bucketName)
          .remove([filePath]);
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

