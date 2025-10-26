import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'post_model.dart';

class PostsProvider with ChangeNotifier {
  final String baseUrl = 'https://jsonplaceholder.typicode.com/posts';
  List<Post> _posts = [];
  bool _isLoading = false;
  String? _errorMessage;
  String? _successMessage;

  List<Post> get posts => _posts;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  String? get successMessage => _successMessage;

  Future<void> fetchAllPosts() async {
    _isLoading = true;
    _errorMessage = null;
    _successMessage = null;
    notifyListeners();
    try {
      final response = await http.get(Uri.parse(baseUrl));
      if (response.statusCode == 200) {
        List<dynamic> data = jsonDecode(response.body);
        _posts = data.map((e) => Post.fromJson(e)).toList();
      } else {
        _errorMessage = 'Không thể tải dữ liệu (${response.statusCode})';
      }
    } catch (e) {
      _errorMessage = 'Lỗi: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<Post?> fetchPostById(int id) async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/$id'));
      if (response.statusCode == 200) {
        return Post.fromJson(jsonDecode(response.body));
      } else {
        _errorMessage = 'Không tìm thấy bài đăng ID $id';
        notifyListeners();
        return null;
      }
    } catch (e) {
      _errorMessage = 'Lỗi khi tìm kiếm: $e';
      notifyListeners();
      return null;
    }
  }

  Future<void> addPost(String title, String body) async {
    _isLoading = true;
    _successMessage = null;
    _errorMessage = null;
    notifyListeners();
    try {
      final response = await http.post(
        Uri.parse(baseUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'title': title, 'body': body, 'userId': 1}),
      );

      if (response.statusCode == 201) {
        final data = jsonDecode(response.body);
        final newPost = Post.fromJson(data);
        _posts.insert(0, newPost);
        _successMessage = 'Tạo bài viết mới thành công!';
      } else {
        _errorMessage = 'Không thể tạo bài viết (${response.statusCode})';
      }
    } catch (e) {
      _errorMessage = 'Lỗi khi thêm bài viết: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> deletePost(int id) async {
    try {
      final response = await http.delete(Uri.parse('$baseUrl/$id'));
      if (response.statusCode == 200) {
        _posts.removeWhere((post) => post.id == id);
        _successMessage = 'Đã xóa bài viết ID $id';
      } else {
        _errorMessage = 'Không thể xóa bài viết (${response.statusCode})';
      }
    } catch (e) {
      _errorMessage = 'Lỗi khi xóa: $e';
    } finally {
      notifyListeners();
    }
  }
}
