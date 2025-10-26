import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'post_provider.dart';
import 'post_model.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final TextEditingController _searchController = TextEditingController();
  Post? _searchedPost;

  @override
  void initState() {
    super.initState();
    Provider.of<PostsProvider>(context, listen: false).fetchAllPosts();
  }

  void _searchById() async {
    final idText = _searchController.text.trim();
    if (idText.isEmpty) return;
    final id = int.tryParse(idText);
    if (id == null) return;

    final provider = Provider.of<PostsProvider>(context, listen: false);
    final result = await provider.fetchPostById(id);
    setState(() {
      _searchedPost = result;
    });
  }

  void _addNewPost() {
    final titleController = TextEditingController();
    final bodyController = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Tạo bài viết mới'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: titleController, decoration: const InputDecoration(labelText: 'Tiêu đề')),
            TextField(controller: bodyController, decoration: const InputDecoration(labelText: 'Nội dung')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Hủy')),
          ElevatedButton(
            onPressed: () {
              Provider.of<PostsProvider>(context, listen: false).addPost(
                titleController.text,
                bodyController.text,
              );
              Navigator.pop(context);
            },
            child: const Text('Thêm'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<PostsProvider>(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Danh sách bài viết'),
        centerTitle: true,
        actions: [
          IconButton(icon: const Icon(Icons.add), onPressed: _addNewPost),
          IconButton(icon: const Icon(Icons.refresh), onPressed: provider.fetchAllPosts),
        ],
      ),
      body: provider.isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Tìm bài theo ID',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      IconButton(icon: const Icon(Icons.search), onPressed: _searchById),
                    ],
                  ),
                ),
                Expanded(
                  child: _searchedPost != null
                      ? ListView(children: [_buildPostCard(_searchedPost!, provider)])
                      : ListView.builder(
                          itemCount: provider.posts.length,
                          itemBuilder: (_, i) => _buildPostCard(provider.posts[i], provider),
                        ),
                ),
              ],
            ),
    );
  }

  Widget _buildPostCard(Post post, PostsProvider provider) {
  return Card(
    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    child: ListTile(
      title: Text(
        post.title,
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 4),
          Text(
            'ID: ${post.id} | UserID: ${post.userId}',
            style: const TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 4),
          Text(post.body),
        ],
      ),
      trailing: IconButton(
        icon: const Icon(Icons.delete, color: Colors.red),
        onPressed: () => provider.deletePost(post.id),
      ),
    ),
  );
}

}
