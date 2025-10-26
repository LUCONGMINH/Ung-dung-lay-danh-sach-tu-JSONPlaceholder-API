import 'package:flutter/material.dart';
import 'dart:async';
import 'package:provider/provider.dart';
import 'package:dio/dio.dart';

class Post {
  final int userId;
  final int id;
  final String title;
  final String body;

  Post({
    required this.userId,
    required this.id,
    required this.title,
    required this.body,
  });

  factory Post.fromJson(Map<String, dynamic> json) {
    return Post(
      userId: json['userId'] as int,
      id: json['id'] as int,
      title: json['title'] as String,
      body: json['body'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'userId': userId,
      'id': id,
      'title': title,
      'body': body,
    };
  }
}

const String _baseUrl = 'https://jsonplaceholder.typicode.com/posts';

typedef TokenGetter = String? Function();

class AuthInterceptor extends Interceptor {
  final TokenGetter _getToken;

  AuthInterceptor(this._getToken);

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final String? token = _getToken();
    if (token != null && token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $token';
      debugPrint('AuthInterceptor: Added Authorization header with token.');
    } else {
      debugPrint('AuthInterceptor: No authentication token found.');
    }
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (err.response?.statusCode == 401 || err.response?.statusCode == 403) {
      debugPrint(
          'AuthInterceptor: Authentication error - ${err.response?.statusCode}');
    }
    handler.next(err);
  }
}

class RetryInterceptor extends Interceptor {
  final Dio dio;
  final int retryLimit;
  final Duration retryDelay;

  RetryInterceptor({
    required this.dio,
    this.retryLimit = 2,
    this.retryDelay = const Duration(seconds: 1),
  });

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    final bool canRetry = err.type == DioExceptionType.connectionTimeout ||
        err.type == DioExceptionType.receiveTimeout ||
        err.type == DioExceptionType.unknown;

    int retryCount = err.requestOptions.extra['retry_count'] as int? ?? 0;

    if (canRetry && retryCount < retryLimit) {
      retryCount++;
      err.requestOptions.extra['retry_count'] = retryCount;
      debugPrint(
          'RetryInterceptor: Retrying request (attempt $retryCount/$retryLimit) for ${err.requestOptions.path}');
      await Future<void>.delayed(retryDelay);

      try {
        final Response<dynamic> response =
            await dio.fetch<dynamic>(err.requestOptions);
        handler.resolve(response);
      } on DioException catch (e) {
        handler.next(e);
      }
    } else {
      handler.next(err);
    }
  }
}

class NetworkService {
  final Dio _dio;

  NetworkService({List<Interceptor>? additionalInterceptors})
      : _dio = Dio(
          BaseOptions(
            baseUrl: _baseUrl,
            connectTimeout: const Duration(seconds: 5),
            receiveTimeout: const Duration(seconds: 3),
            headers: <String, String>{
              'Content-Type': 'application/json; charset=UTF-8',
            },
          ),
        ) {
    // Removed LogInterceptor as per request.
    if (additionalInterceptors != null) {
      _dio.interceptors.addAll(additionalInterceptors);
    }
    _dio.interceptors.add(
      RetryInterceptor(
        dio: _dio,
        retryLimit: 2,
        retryDelay: const Duration(seconds: 1),
      ),
    );
  }

  String _formatDioError(DioException e) {
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.sendTimeout) {
      return 'Connection error: Timeout. Please try again.';
    } else if (e.type == DioExceptionType.badResponse) {
      final int? statusCode = e.response?.statusCode;
      final dynamic data = e.response?.data;
      String message = 'Server error ($statusCode)';
      if (data != null && data is Map<String, dynamic> && data.containsKey('message')) {
        message += ': ${data['message']}';
      } else if (e.message != null) {
        message += ': ${e.message}';
      }
      return message;
    } else if (e.type == DioExceptionType.cancel) {
      return 'Request was cancelled.';
    } else if (e.type == DioExceptionType.unknown) {
      return 'Unknown network error: Please check your internet connection and try again.';
    }
    return 'A network error occurred: ${e.message}';
  }

  Future<List<Post>> fetchAllPosts() async {
    try {
      final Response<dynamic> response = await _dio.get<dynamic>('');

      if (response.statusCode == 200) {
        final List<dynamic> jsonList = response.data as List<dynamic>;
        return jsonList
            .map<Post>((dynamic postJson) =>
                Post.fromJson(postJson as Map<String, dynamic>))
            .toList();
      } else {
        throw Exception(
            'Failed to load posts list: Status code ${response.statusCode}');
      }
    } on DioException catch (e) {
      throw Exception(_formatDioError(e));
    } catch (e) {
      throw Exception('An error occurred while loading posts list: $e');
    }
  }

  Future<Post?> fetchPostById(int id) async {
    try {
      final Response<dynamic> response = await _dio.get<dynamic>('/$id');

      if (response.statusCode == 200) {
        return Post.fromJson(response.data as Map<String, dynamic>);
      } else if (response.statusCode == 404) {
        return null;
      } else {
        throw Exception(
            'Failed to load post ID $id: Status code ${response.statusCode}');
      }
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        return null;
      }
      throw Exception(_formatDioError(e));
    } catch (e) {
      throw Exception('An error occurred while loading post ID $id: $e');
    }
  }

  Future<Post> createPost(String title, String body, int userId) async {
    try {
      final Response<dynamic> response = await _dio.post<dynamic>(
        '',
        data: <String, dynamic>{
          'title': title,
          'body': body,
          'userId': userId,
        },
      );

      if (response.statusCode == 201) {
        return Post.fromJson(response.data as Map<String, dynamic>);
      } else {
        throw Exception(
            'Failed to create post: Status code ${response.statusCode}');
      }
    } on DioException catch (e) {
      throw Exception(_formatDioError(e));
    } catch (e) {
      throw Exception('An error occurred while creating post: $e');
    }
  }

  Future<Post> updatePost(int id, String title, String body, int userId) async {
    try {
      final Response<dynamic> response = await _dio.put<dynamic>(
        '/$id',
        data: <String, dynamic>{
          'id': id,
          'title': title,
          'body': body,
          'userId': userId,
        },
      );

      if (response.statusCode == 200) {
        return Post.fromJson(response.data as Map<String, dynamic>);
      } else {
        throw Exception(
            'Failed to update post ID $id: Status code ${response.statusCode}');
      }
    } on DioException catch (e) {
      throw Exception(_formatDioError(e));
    } catch (e) {
      throw Exception('An error occurred while updating post ID $id: $e');
    }
  }

  Future<void> deletePost(int id) async {
    try {
      final Response<dynamic> response = await _dio.delete<dynamic>(
        '/$id',
      );

      if (response.statusCode == 200 || response.statusCode == 204) {
      } else {
        throw Exception(
            'Failed to delete post ID $id: Status code ${response.statusCode}');
      }
    } on DioException catch (e) {
      throw Exception(_formatDioError(e));
    } catch (e) {
      throw Exception('An error occurred while deleting post ID $id: $e');
    }
  }
}

class User {
  final String username;
  final String authToken;

  User({required this.username, required this.authToken});
}

class AuthService with ChangeNotifier {
  User? _currentUser;
  String? _authToken;
  String? _errorMessage;
  String? _successMessage;

  User? get currentUser => _currentUser;
  String? get authToken => _authToken;
  bool get isAuthenticated => _authToken != null;
  String? get errorMessage => _errorMessage;
  String? get successMessage => _successMessage;

  void clearMessages() {
    _errorMessage = null;
    _successMessage = null;
    notifyListeners();
  }

  Future<void> login(String username, String password) async {
    clearMessages();
    await Future<void>.delayed(const Duration(milliseconds: 500));

    if (username == 'admin' && password == 'admin') {
      _authToken = 'simulated_jwt_for_$username';
      _currentUser = User(username: username, authToken: _authToken!);
      _successMessage = 'Login successful for user: $username';
      notifyListeners();
    } else {
      _errorMessage = 'Incorrect username or password.';
      notifyListeners();
    }
  }

  void logout() {
    _currentUser = null;
    _authToken = null;
    clearMessages();
    _successMessage = 'Logout successful!';
    notifyListeners();
  }
}

class PostsProvider with ChangeNotifier {
  late final NetworkService _networkService;
  List<Post> _posts = <Post>[];
  Post? _currentSearchedPost;
  bool _isLoading = false;
  String? _errorMessage;
  String? _successMessage;
  bool _isSearchingById = false;

  final AuthService _authService;

  PostsProvider({NetworkService? networkService, required AuthService authService})
      : _authService = authService {
    _networkService = networkService ??
        NetworkService(
          additionalInterceptors: <Interceptor>[
            AuthInterceptor(() => _authService.authToken),
          ],
        );
    _authService.addListener(_onAuthServiceChanged);
    _fetchAllPosts();
  }

  @override
  void dispose() {
    _authService.removeListener(_onAuthServiceChanged);
    super.dispose();
  }

  void _onAuthServiceChanged() {
    clearMessages();

    if (_authService.errorMessage != null) {
      _errorMessage = _authService.errorMessage;
    } else if (_authService.successMessage != null) {
      _successMessage = _authService.successMessage;
    }
    _authService.clearMessages();

    _fetchAllPosts();
    notifyListeners();
  }

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  String? get successMessage => _successMessage;
  List<Post> get posts => _posts;
  Post? get currentSearchedPost => _currentSearchedPost;
  bool get isSearchingById => _isSearchingById;
  bool get isAuthenticated => _authService.isAuthenticated;

  void clearMessages() {
    _errorMessage = null;
    _successMessage = null;
  }

  Future<void> _fetchAllPosts() async {
    _isLoading = true;
    notifyListeners();
    try {
      _posts = await _networkService.fetchAllPosts();
      if (_posts.isEmpty &&
          !isAuthenticated &&
          _errorMessage == null &&
          _successMessage == null) {
        _successMessage =
            'You need to log in to view posts or perform actions.';
      }
    } on Exception catch (e) {
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> searchPostById(int id) async {
    _isLoading = true;
    clearMessages();
    _currentSearchedPost = null;
    _isSearchingById = true;
    notifyListeners();
    try {
      _currentSearchedPost = await _networkService.fetchPostById(id);
      if (_currentSearchedPost == null) {
        _errorMessage = 'No post found with this ID ($id).';
      }
    } on Exception catch (e) {
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void clearSearch() {
    _isSearchingById = false;
    _currentSearchedPost = null;
    clearMessages();
    _fetchAllPosts();
  }

  Future<void> addPost(String title, String body) async {
    _isLoading = true;
    clearMessages();
    notifyListeners();
    try {
      final Post newPost =
          await _networkService.createPost(title, body, 1);
      _posts.insert(0, newPost);
      _successMessage = 'Post "${newPost.title}" created successfully (ID: ${newPost.id})!';
    } on Exception catch (e) {
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> updatePost(int id, String title, String body, int userId) async {
    _isLoading = true;
    clearMessages();
    notifyListeners();
    try {
      final Post updated =
          await _networkService.updatePost(id, title, body, userId);
      final int index = _posts.indexWhere((Post post) => post.id == id);
      if (index != -1) {
        _posts[index] = updated;
      }
      if (_currentSearchedPost?.id == id) {
        _currentSearchedPost = updated;
      }
      _successMessage = 'Post ID $id updated successfully!';
    } on Exception catch (e) {
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> deletePost(int id) async {
    _isLoading = true;
    clearMessages();
    notifyListeners();
    try {
      await _networkService.deletePost(id);
      _posts.removeWhere((Post post) => post.id == id);
      if (_currentSearchedPost?.id == id) {
        _currentSearchedPost = null;
        _isSearchingById = false;
      }
      _successMessage = 'Post ID $id deleted successfully!';
    } on Exception catch (e) {
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthService>(
          create: (BuildContext context) => AuthService(),
        ),
        ChangeNotifierProxyProvider<AuthService, PostsProvider>(
          create: (BuildContext context) => PostsProvider(
            authService: Provider.of<AuthService>(context, listen: false),
          ),
          update: (
            BuildContext context,
            AuthService authService,
            PostsProvider? previousPostsProvider,
          ) {
            return previousPostsProvider ?? PostsProvider(authService: authService);
          },
        ),
      ],
      builder: (BuildContext context, Widget? child) {
        return MaterialApp(
          title: 'Post Management',
          theme: ThemeData(
            primarySwatch: Colors.blue,
            visualDensity: VisualDensity.adaptivePlatformDensity,
            appBarTheme: const AppBarTheme(
              backgroundColor: Colors.blueAccent,
              foregroundColor: Colors.white,
            ),
            useMaterial3: true,
          ),
          home: const HomeView(),
        );
      },
    );
  }
}

class HomeView extends StatefulWidget {
  const HomeView({super.key});

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final GlobalKey<ScaffoldMessengerState> _scaffoldMessengerKey =
      GlobalKey<ScaffoldMessengerState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final PostsProvider postsProvider =
          Provider.of<PostsProvider>(context, listen: false);
      postsProvider.addListener(_handleProviderMessages);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    final PostsProvider postsProvider =
        Provider.of<PostsProvider>(context, listen: false);
    postsProvider.removeListener(_handleProviderMessages);
    super.dispose();
  }

  void _handleProviderMessages() {
    final PostsProvider postsProvider =
        Provider.of<PostsProvider>(context, listen: false);
    bool messageShown = false;
    if (postsProvider.errorMessage != null) {
      _showSnackBar(postsProvider.errorMessage!, isError: true);
      messageShown = true;
    } else if (postsProvider.successMessage != null) {
      _showSnackBar(postsProvider.successMessage!, isError: false);
      messageShown = true;
    }

    if (messageShown) {
      postsProvider.clearMessages();
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (_scaffoldMessengerKey.currentState != null &&
        _scaffoldMessengerKey.currentState!.mounted) {
      _scaffoldMessengerKey.currentState!.showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError ? Colors.red.shade700 : Colors.green.shade700,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  void _searchPostById() {
    final String idText = _searchController.text.trim();
    if (idText.isNotEmpty) {
      final int? postId = int.tryParse(idText);
      if (postId != null) {
        Provider.of<PostsProvider>(context, listen: false).searchPostById(postId);
      } else {
        _showSnackBar('Please enter a valid ID number.', isError: true);
      }
    } else {
      _showSnackBar('Please enter a post ID to search.', isError: true);
    }
  }

  void _clearSearch() {
    Provider.of<PostsProvider>(context, listen: false).clearSearch();
    _searchController.clear();
  }

  Future<void> _showPostFormDialog({Post? post}) async {
    final TextEditingController titleController =
        TextEditingController(text: post?.title);
    final TextEditingController bodyController =
        TextEditingController(text: post?.body);

    await showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text(post == null ? 'Create New Post' : 'Edit Post'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                TextField(
                  controller: titleController,
                  decoration: const InputDecoration(labelText: 'Title'),
                ),
                TextField(
                  controller: bodyController,
                  decoration: const InputDecoration(labelText: 'Body'),
                  maxLines: 3,
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final String title = titleController.text.trim();
                final String body = bodyController.text.trim();
                if (title.isNotEmpty && body.isNotEmpty) {
                  final PostsProvider postsProvider =
                      Provider.of<PostsProvider>(context, listen: false);
                  if (post == null) {
                    postsProvider.addPost(title, body);
                  } else {
                    postsProvider.updatePost(post.id, title, body, post.userId);
                  }
                  Navigator.of(dialogContext).pop();
                } else {
                  _showSnackBar(
                      'Title and Body cannot be empty.', isError: true);
                }
              },
              child: Text(post == null ? 'Create' : 'Update'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showDeleteConfirmationDialog(Post post) async {
    await showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Confirm Deletion'),
          content: Text(
              'Are you sure you want to delete the post "${post.title}" (ID: ${post.id})?'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Provider.of<PostsProvider>(context, listen: false)
                    .deletePost(post.id);
                Navigator.of(dialogContext).pop();
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Delete', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ScaffoldMessenger(
      key: _scaffoldMessengerKey,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Post Management'),
          centerTitle: true,
          actions: <Widget>[
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () => Provider.of<PostsProvider>(context, listen: false)
                  .clearSearch(),
              tooltip: 'Refresh all posts',
            ),
          ],
        ),
        drawer: Drawer(
          child: Consumer<AuthService>(
            builder: (BuildContext context, AuthService authService, Widget? child) {
              return ListView(
                padding: EdgeInsets.zero,
                children: <Widget>[
                  DrawerHeader(
                    decoration: const BoxDecoration(
                      color: Colors.blueAccent,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const Text(
                          'Options',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Status: ${authService.isAuthenticated ? 'Logged In' : 'Logged Out'}',
                          style: TextStyle(
                            color: authService.isAuthenticated
                                ? Colors.greenAccent
                                : Colors.white70,
                            fontSize: 14,
                          ),
                        ),
                        if (authService.isAuthenticated && authService.currentUser != null)
                          Text(
                            'User: ${authService.currentUser!.username}',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        if (!authService.isAuthenticated) ...<Widget>[
                          TextField(
                            controller: _usernameController,
                            decoration: const InputDecoration(
                              labelText: 'Username',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _passwordController,
                            decoration: const InputDecoration(
                              labelText: 'Password',
                              border: OutlineInputBorder(),
                            ),
                            obscureText: true,
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            onPressed: () {
                              final String username =
                                  _usernameController.text.trim();
                              final String password =
                                  _passwordController.text.trim();
                              if (username.isNotEmpty && password.isNotEmpty) {
                                authService.login(username, password);
                              } else {
                                _showSnackBar(
                                    'Please enter username and password.',
                                    isError: true);
                              }
                            },
                            icon: const Icon(Icons.login),
                            label: const Text('Login'),
                            style: ElevatedButton.styleFrom(
                              minimumSize: const Size.fromHeight(40),
                            ),
                          ),
                        ] else
                          ElevatedButton.icon(
                            onPressed: () {
                              authService.logout();
                              _usernameController.clear();
                              _passwordController.clear();
                              Navigator.of(context).pop();
                            },
                            icon: const Icon(Icons.logout),
                            label: const Text('Logout'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white,
                              minimumSize: const Size.fromHeight(40),
                            ),
                          ),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        body: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'Search Post by ID',
                        hintText: 'Enter Post ID',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8.0),
                        ),
                        prefixIcon: const Icon(Icons.search),
                      ),
                      onSubmitted: (_) => _searchPostById(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _searchPostById,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          vertical: 16.0, horizontal: 16.0),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8.0),
                      ),
                    ),
                    child: const Text('Search'),
                  ),
                  Consumer<PostsProvider>(
                    builder:
                        (BuildContext context, PostsProvider postsProvider, Widget? child) {
                      if (postsProvider.isSearchingById) {
                        return Row(
                          children: <Widget>[
                            const SizedBox(width: 8),
                            IconButton(
                              icon: const Icon(Icons.clear),
                              tooltip: 'Show all posts',
                              onPressed: _clearSearch,
                              style: IconButton.styleFrom(
                                backgroundColor: Colors.grey.shade200,
                                foregroundColor: Colors.black87,
                              ),
                            ),
                          ],
                        );
                      }
                      return const SizedBox.shrink();
                    },
                  ),
                ],
              ),
            ),
            Expanded(
              child: Consumer<PostsProvider>(
                builder:
                    (BuildContext context, PostsProvider postsProvider, Widget? child) {
                  if (postsProvider.isLoading) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (postsProvider.errorMessage != null &&
                      !postsProvider.isSearchingById &&
                      postsProvider.posts.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Text(
                          'Error: ${postsProvider.errorMessage}',
                          textAlign: TextAlign.center,
                          style:
                              const TextStyle(color: Colors.redAccent, fontSize: 16),
                        ),
                      ),
                    );
                  }

                  if (!postsProvider.isAuthenticated &&
                      postsProvider.posts.isEmpty &&
                      !postsProvider.isSearchingById) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(16.0),
                        child: Text(
                          'You need to log in to view posts or perform actions.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 16, color: Colors.grey),
                        ),
                      ),
                    );
                  }

                  if (postsProvider.isSearchingById) {
                    if (postsProvider.currentSearchedPost != null) {
                      return SingleChildScrollView(
                        child: PostCard(
                          post: postsProvider.currentSearchedPost!,
                          onEdit: postsProvider.isAuthenticated
                              ? () => _showPostFormDialog(
                                  post: postsProvider.currentSearchedPost!)
                              : null,
                          onDelete: postsProvider.isAuthenticated
                              ? () => _showDeleteConfirmationDialog(
                                  postsProvider.currentSearchedPost!)
                              : null,
                        ),
                      );
                    } else if (postsProvider.errorMessage != null) {
                      return Center(child: Text(postsProvider.errorMessage!));
                    } else {
                      return const Center(child: Text('No post found.'));
                    }
                  } else {
                    if (postsProvider.posts.isNotEmpty) {
                      return ListView.builder(
                        itemCount: postsProvider.posts.length,
                        itemBuilder: (BuildContext context, int index) {
                          final Post post = postsProvider.posts[index];
                          return PostCard(
                            post: post,
                            onEdit: postsProvider.isAuthenticated
                                ? () => _showPostFormDialog(post: post)
                                : null,
                            onDelete: postsProvider.isAuthenticated
                                ? () => _showDeleteConfirmationDialog(post)
                                : null,
                          );
                        },
                      );
                    } else {
                      return const Center(child: Text('No posts available.'));
                    }
                  }
                },
              ),
            ),
          ],
        ),
        floatingActionButton: Consumer<PostsProvider>(
          builder: (BuildContext context, PostsProvider postsProvider, Widget? child) {
            return FloatingActionButton(
              onPressed: postsProvider.isAuthenticated
                  ? () => _showPostFormDialog()
                  : null,
              tooltip: postsProvider.isAuthenticated
                  ? 'Create new post'
                  : 'You need to log in to create a post',
              backgroundColor: postsProvider.isAuthenticated
                  ? Theme.of(context).colorScheme.primary
                  : Colors.grey,
              child: const Icon(Icons.add, color: Colors.white),
            );
          },
        ),
      ),
    );
  }
}

class PostCard extends StatelessWidget {
  final Post post;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const PostCard({
    required this.post,
    this.onEdit,
    this.onDelete,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      elevation: 4.0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10.0),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Post ID: ${post.id}',
              style: const TextStyle(
                fontSize: 14,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              post.title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.deepPurple,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              post.body,
              style: const TextStyle(fontSize: 16, color: Colors.black87),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Text(
                  'User ID: ${post.userId}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                    color: Colors.blueGrey,
                  ),
                ),
                Row(
                  children: <Widget>[
                    if (onEdit != null)
                      IconButton(
                        icon: const Icon(Icons.edit, size: 20),
                        color: Colors.blue,
                        onPressed: onEdit,
                        tooltip: 'Edit post',
                      ),
                    if (onDelete != null)
                      IconButton(
                        icon: const Icon(Icons.delete, size: 20),
                        color: Colors.red,
                        onPressed: onDelete,
                        tooltip: 'Delete post',
                      ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}