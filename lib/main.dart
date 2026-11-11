import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;

const kCategories = ['Tất cả', 'Hành động', 'Fantasy', 'Tình cảm', 'Hài hước', 'Phiêu lưu'];
const kPending = 'Chờ duyệt';
const kApproved = 'Đã duyệt';
const kRejected = 'Từ chối';
const kRatePerView = 50; // đồng / lượt xem hợp lệ

String money(int v) {
  final s = v.toString();
  final b = StringBuffer();
  for (int i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write('.');
    b.write(s[i]);
  }
  return '$b đ';
}

String roleLabel(String? r) => r == 'Admin' ? 'Quản trị viên' : r == 'Author' ? 'Tác giả' : 'Người đọc';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DB.init();
  runApp(const MyApp());
}

class DB {
  static late Database db;

  static Future<void> init() async {
    db = await openDatabase(
      p.join(await getDatabasesPath(), 'truyen.db'),
      version: 6,
      onCreate: (db, version) async {
        await db.execute('''CREATE TABLE users(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          username TEXT, password TEXT, role TEXT, pen_name TEXT DEFAULT '')''');
        await db.execute('''CREATE TABLE stories(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          title TEXT, author TEXT, category TEXT, hot INTEGER,
          description TEXT DEFAULT '', status TEXT DEFAULT 'Đang cập nhật', image_url TEXT DEFAULT '', content TEXT DEFAULT '',
          owner_id INTEGER DEFAULT 0, approval TEXT DEFAULT 'Đã duyệt', views INTEGER DEFAULT 0, reject_reason TEXT DEFAULT '')''');
        await db.execute('''CREATE TABLE favorites(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          user_id INTEGER NOT NULL, story_id INTEGER NOT NULL,
          UNIQUE(user_id, story_id))''');
        await db.execute('''CREATE TABLE ratings(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          user_id INTEGER NOT NULL, story_id INTEGER NOT NULL,
          stars INTEGER NOT NULL CHECK(stars BETWEEN 1 AND 5),
          UNIQUE(user_id, story_id))''');
        await _createV6Tables(db);
        await seed(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute("ALTER TABLE stories ADD COLUMN description TEXT DEFAULT ''");
          await db.execute("ALTER TABLE stories ADD COLUMN status TEXT DEFAULT 'Đang cập nhật'");
          await db.execute('''CREATE TABLE IF NOT EXISTS favorites(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id INTEGER NOT NULL, story_id INTEGER NOT NULL,
            UNIQUE(user_id, story_id))''');
        }
        if (oldVersion < 3) {
          await db.execute('''CREATE TABLE IF NOT EXISTS ratings(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id INTEGER NOT NULL, story_id INTEGER NOT NULL,
            stars INTEGER NOT NULL CHECK(stars BETWEEN 1 AND 5),
            UNIQUE(user_id, story_id))''');
        }
        if (oldVersion < 4) {
          await db.execute("ALTER TABLE stories ADD COLUMN image_url TEXT DEFAULT ''");
        }
        if (oldVersion < 5) {
          await db.execute("ALTER TABLE stories ADD COLUMN content TEXT DEFAULT ''");
        }
        if (oldVersion < 6) {
          await db.execute("ALTER TABLE users ADD COLUMN pen_name TEXT DEFAULT ''");
          await db.execute("ALTER TABLE stories ADD COLUMN owner_id INTEGER DEFAULT 0");
          await db.execute("ALTER TABLE stories ADD COLUMN approval TEXT DEFAULT 'Đã duyệt'");
          await db.execute("ALTER TABLE stories ADD COLUMN views INTEGER DEFAULT 0");
          await db.execute("ALTER TABLE stories ADD COLUMN reject_reason TEXT DEFAULT ''");
          await _createV6Tables(db);
          await db.insert('users', {'username': 'author', 'password': '123456', 'role': 'Author', 'pen_name': 'Tác Giả Demo'});
        }
      },
    );
  }

  static Future<void> _createV6Tables(Database db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS author_requests(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      user_id INTEGER NOT NULL, pen_name TEXT, reason TEXT,
      status TEXT DEFAULT 'Chờ duyệt')''');
    await db.execute('''CREATE TABLE IF NOT EXISTS story_views(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      user_id INTEGER NOT NULL, story_id INTEGER NOT NULL, day TEXT NOT NULL,
      UNIQUE(user_id, story_id, day))''');
  }

  static Future<void> seed(Database db) async {
    await db.insert('users', {'username': 'admin', 'password': '123456', 'role': 'Admin'});
    await db.insert('users', {'username': 'reader', 'password': '123456', 'role': 'Reader'});
    await db.insert('users', {'username': 'author', 'password': '123456', 'role': 'Author', 'pen_name': 'Tác Giả Demo'});
    final samples = [
      ['Kiếm Sĩ Bình Minh', 'Lam Phong', 'Hành động', 1, 'Một kiếm sĩ trẻ bắt đầu hành trình tìm lại ánh sáng cho vương quốc.', 'Đang cập nhật'],
      ['Thế Giới Phép Thuật', 'Mộc Miên', 'Fantasy', 1, 'Một thế giới nơi phép thuật và những bí mật cổ xưa cùng tồn tại.', 'Đang cập nhật'],
      ['Mùa Hạ Có Cậu', 'An Nhiên', 'Tình cảm', 0, 'Câu chuyện nhẹ nhàng về tình bạn và những rung động đầu đời.', 'Đã hoàn thành'],
      ['Đầu Bếp Vạn Năng', 'Bếp Nhỏ', 'Hài hước', 0, 'Những tình huống dở khóc dở cười trong căn bếp đặc biệt.', 'Đang cập nhật'],
      ['Bản Đồ Bí Ẩn', 'Hải Đăng', 'Phiêu lưu', 1, 'Nhóm bạn lên đường giải mã tấm bản đồ bí ẩn.', 'Đang cập nhật'],
    ];
    for (final s in samples) {
      await db.insert('stories', {'title': s[0], 'author': s[1], 'category': s[2], 'hot': s[3], 'description': s[4], 'status': s[5]});
    }
  }

  // ---------- Users / quyền ----------
  static Future<Map<String, Object?>?> getUser(int id) async {
    final r = await db.query('users', where: 'id=?', whereArgs: [id], limit: 1);
    return r.isEmpty ? null : r.first;
  }

  static Future<bool> isAdmin(int userId) async => (await getUser(userId))?['role'] == 'Admin';

  /// Admin sửa được mọi truyện. Tác giả chỉ sửa/xóa truyện có owner_id là của mình.
  static Future<bool> canModify(int userId, int storyId) async {
    final u = await getUser(userId);
    if (u == null) return false;
    if (u['role'] == 'Admin') return true;
    if (u['role'] != 'Author') return false;
    final r = await db.query('stories', columns: ['owner_id'], where: 'id=?', whereArgs: [storyId], limit: 1);
    return r.isNotEmpty && r.first['owner_id'] == userId;
  }

  // ---------- Truyện ----------
  static Future<bool> saveStory(int userId, Map<String, Object?> values, {int? storyId}) async {
    final u = await getUser(userId);
    if (u == null) return false;
    final role = u['role'];
    final v = Map<String, Object?>.from(values);
    if (role == 'Author') {
      final pen = (u['pen_name'] as String? ?? '').trim();
      v['author'] = pen.isEmpty ? u['username'] : pen;
      v['hot'] = 0; // tác giả không tự đặt HOT
      v['approval'] = kPending; // thêm/sửa đều phải xét duyệt lại
      v['reject_reason'] = '';
    }
    if (storyId == null) {
      if (role == 'Admin') {
        v['owner_id'] = userId;
        v['approval'] = kApproved;
      } else if (role == 'Author') {
        v['owner_id'] = userId;
      } else {
        return false;
      }
      await db.insert('stories', v);
      return true;
    }
    if (!await canModify(userId, storyId)) return false;
    await db.update('stories', v, where: 'id=?', whereArgs: [storyId]);
    return true;
  }

  static Future<bool> deleteStory(int userId, int storyId) async {
    if (!await canModify(userId, storyId)) return false;
    await db.delete('favorites', where: 'story_id=?', whereArgs: [storyId]);
    await db.delete('ratings', where: 'story_id=?', whereArgs: [storyId]);
    await db.delete('story_views', where: 'story_id=?', whereArgs: [storyId]);
    await db.delete('stories', where: 'id=?', whereArgs: [storyId]);
    return true;
  }

  static Future<List<Map<String, Object?>>> getStories() =>
      db.query('stories', where: 'approval=?', whereArgs: [kApproved], orderBy: 'hot DESC, title ASC');

  static Future<List<Map<String, Object?>>> getOwnStories(int ownerId) =>
      db.query('stories', where: 'owner_id=?', whereArgs: [ownerId], orderBy: 'id DESC');

  static Future<List<Map<String, Object?>>> getPendingStories() =>
      db.query('stories', where: 'approval=?', whereArgs: [kPending], orderBy: 'id ASC');

  static Future<bool> reviewStory(int adminId, int storyId, bool approve, [String reason = '']) async {
    if (!await isAdmin(adminId)) return false;
    await db.update('stories', {'approval': approve ? kApproved : kRejected, 'reject_reason': approve ? '' : reason},
        where: 'id=?', whereArgs: [storyId]);
    return true;
  }

  // ---------- Lượt xem (tính tiền) ----------
  /// Mỗi người đọc chỉ tính 1 lượt / truyện / ngày, tác giả đọc truyện của mình không tính.
  static Future<void> registerView(int userId, int storyId) async {
    final s = await db.query('stories', columns: ['owner_id', 'approval'], where: 'id=?', whereArgs: [storyId], limit: 1);
    if (s.isEmpty || s.first['approval'] != kApproved || s.first['owner_id'] == userId) return;
    final day = DateTime.now().toIso8601String().substring(0, 10);
    final ex = await db.query('story_views', where: 'user_id=? AND story_id=? AND day=?', whereArgs: [userId, storyId, day], limit: 1);
    if (ex.isNotEmpty) return;
    await db.insert('story_views', {'user_id': userId, 'story_id': storyId, 'day': day});
    await db.rawUpdate('UPDATE stories SET views=COALESCE(views,0)+1 WHERE id=?', [storyId]);
  }

  // ---------- Yêu cầu làm tác giả ----------
  static Future<Map<String, Object?>?> getMyRequest(int userId) async {
    final r = await db.query('author_requests', where: 'user_id=?', whereArgs: [userId], orderBy: 'id DESC', limit: 1);
    return r.isEmpty ? null : r.first;
  }

  static Future<bool> submitAuthorRequest(int userId, String penName, String reason) async {
    final u = await getUser(userId);
    if (u == null || u['role'] != 'Reader') return false;
    final last = await getMyRequest(userId);
    if (last != null && last['status'] == kPending) return false;
    await db.insert('author_requests', {'user_id': userId, 'pen_name': penName, 'reason': reason, 'status': kPending});
    return true;
  }

  static Future<List<Map<String, Object?>>> getPendingRequests() => db.rawQuery('''SELECT r.*, u.username FROM author_requests r
      INNER JOIN users u ON u.id=r.user_id WHERE r.status=? ORDER BY r.id ASC''', [kPending]);

  static Future<bool> reviewRequest(int adminId, int requestId, bool approve) async {
    if (!await isAdmin(adminId)) return false;
    final r = await db.query('author_requests', where: 'id=?', whereArgs: [requestId], limit: 1);
    if (r.isEmpty) return false;
    await db.update('author_requests', {'status': approve ? kApproved : kRejected}, where: 'id=?', whereArgs: [requestId]);
    if (approve) {
      await db.update('users', {'role': 'Author', 'pen_name': r.first['pen_name']},
          where: "id=? AND role='Reader'", whereArgs: [r.first['user_id']]);
    }
    return true;
  }

  static Future<int> pendingTotal() async {
    final a = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM stories WHERE approval=?', [kPending])) ?? 0;
    final b = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM author_requests WHERE status=?', [kPending])) ?? 0;
    return a + b;
  }

  // ---------- Yêu thích ----------
  static Future<bool> isFavorite(int userId, int storyId) async {
    final rows = await db.query('favorites', where: 'user_id=? AND story_id=?', whereArgs: [userId, storyId]);
    return rows.isNotEmpty;
  }

  static Future<void> toggleFavorite(int userId, int storyId) async {
    final exists = await isFavorite(userId, storyId);
    if (exists) {
      await db.delete('favorites', where: 'user_id=? AND story_id=?', whereArgs: [userId, storyId]);
    } else {
      await db.insert('favorites', {'user_id': userId, 'story_id': storyId}, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  static Future<List<Map<String, Object?>>> getFavorites(int userId) async {
    return db.rawQuery('''SELECT stories.* FROM stories
      INNER JOIN favorites ON stories.id=favorites.story_id
      WHERE favorites.user_id=? AND stories.approval=? ORDER BY stories.title''', [userId, kApproved]);
  }
}

// ======================= Form thêm / sửa truyện (dùng chung) =======================
Future<Map<String, Object?>?> showStoryEditor(BuildContext context, {Map<String, Object?>? story, String? lockedAuthor, bool allowHot = true}) async {
  final title = TextEditingController(text: story?['title'] as String? ?? '');
  final author = TextEditingController(text: lockedAuthor ?? story?['author'] as String? ?? '');
  final description = TextEditingController(text: story?['description'] as String? ?? '');
  final content = TextEditingController(text: story?['content'] as String? ?? '');
  final imageUrl = TextEditingController(text: story?['image_url'] as String? ?? '');
  String category = story?['category'] as String? ?? kCategories[1];
  String status = story?['status'] as String? ?? 'Đang cập nhật';
  bool hot = story?['hot'] == 1;
  final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
          builder: (ctx, setDialog) => AlertDialog(
            title: Text(story == null ? 'Thêm truyện' : 'Sửa truyện'),
            content: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  TextField(controller: title, decoration: const InputDecoration(labelText: 'Tên truyện')),
                  TextField(controller: author, enabled: lockedAuthor == null, decoration: const InputDecoration(labelText: 'Tác giả')),
                  TextField(controller: description, maxLines: 4, decoration: const InputDecoration(labelText: 'Mô tả nội dung')),
                  const SizedBox(height: 10),
                  TextField(
                      controller: content,
                      maxLines: 12,
                      minLines: 8,
                      decoration: const InputDecoration(
                          labelText: 'Nội dung truyện chữ', hintText: 'Nhập toàn bộ nội dung truyện tại đây...', alignLabelWithHint: true, border: OutlineInputBorder())),
                  TextField(
                      controller: imageUrl,
                      keyboardType: TextInputType.url,
                      decoration: const InputDecoration(labelText: 'Đường dẫn ảnh bìa (URL)', hintText: 'https://example.com/anh-truyen.jpg', prefixIcon: Icon(Icons.image_outlined))),
                  DropdownButtonFormField<String>(
                      value: category,
                      decoration: const InputDecoration(labelText: 'Chủ đề'),
                      items: kCategories.skip(1).map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                      onChanged: (v) {
                        if (v != null) setDialog(() => category = v);
                      }),
                  DropdownButtonFormField<String>(
                      value: status,
                      decoration: const InputDecoration(labelText: 'Trạng thái'),
                      items: ['Đang cập nhật', 'Đã hoàn thành', 'Tạm ngưng'].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                      onChanged: (v) {
                        if (v != null) setDialog(() => status = v);
                      }),
                  if (allowHot) SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Truyện HOT'), value: hot, onChanged: (v) => setDialog(() => hot = v)),
                ])),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(lockedAuthor != null ? 'Gửi duyệt' : 'Lưu')),
            ],
          )));
  Map<String, Object?>? result;
  if (saved == true && title.text.trim().isNotEmpty) {
    result = {
      'title': title.text.trim(),
      'author': author.text.trim(),
      'category': category,
      'hot': hot ? 1 : 0,
      'description': description.text.trim(),
      'status': status,
      'image_url': imageUrl.text.trim(),
      'content': content.text.trim(),
    };
  }
  title.dispose();
  author.dispose();
  description.dispose();
  content.dispose();
  imageUrl.dispose();
  return result;
}

Future<bool> confirmDialog(BuildContext context, String title, String message, String okLabel) async {
  final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(title: Text(title), content: Text(message), actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(okLabel)),
      ]));
  return ok == true;
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Truyện Mộc',
    theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF6044B8),
        scaffoldBackgroundColor: const Color(0xFFF7F6FA),
        cardTheme: const CardThemeData(elevation: 2, margin: EdgeInsets.zero)),
    home: const LoginPage(),
  );
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final username = TextEditingController();
  final password = TextEditingController();
  bool hidePassword = true;
  Future<void> login() async {
    final result = await DB.db.query('users', where: 'username=? AND password=?', whereArgs: [username.text.trim(), password.text]);
    if (!mounted) return;
    if (result.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sai tài khoản hoặc mật khẩu')));
      return;
    }
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => HomePage(user: result.first)));
  }

  @override
  void dispose() {
    username.dispose();
    password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Container(
      decoration: const BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFECE6FF), Color(0xFFF9F7FF), Color(0xFFE3F0F1)])),
      child: Center(
          child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Card(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                  child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        const CircleAvatar(radius: 38, backgroundColor: Color(0xFFEAE3FF), child: Icon(Icons.auto_stories, size: 42, color: Color(0xFF6044B8))),
                        const SizedBox(height: 12),
                        const Text('TRUYỆN MỘC', style: TextStyle(fontSize: 27, fontWeight: FontWeight.bold, letterSpacing: 1)),
                        const Text('Thế giới truyện dành cho bạn', style: TextStyle(color: Colors.grey)),
                        const SizedBox(height: 26),
                        TextField(controller: username, decoration: const InputDecoration(labelText: 'Tên đăng nhập', prefixIcon: Icon(Icons.person_outline), border: OutlineInputBorder())),
                        const SizedBox(height: 14),
                        TextField(
                            controller: password,
                            obscureText: hidePassword,
                            decoration: InputDecoration(
                                labelText: 'Mật khẩu',
                                prefixIcon: const Icon(Icons.lock_outline),
                                border: const OutlineInputBorder(),
                                suffixIcon: IconButton(icon: Icon(hidePassword ? Icons.visibility : Icons.visibility_off), onPressed: () => setState(() => hidePassword = !hidePassword)))),
                        const SizedBox(height: 20),
                        SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(onPressed: login, icon: const Icon(Icons.login), label: const Padding(padding: EdgeInsets.all(12), child: Text('ĐĂNG NHẬP')))),
                        const SizedBox(height: 16),
                        const Text('Admin: admin / 123456'),
                        const Text('Tác giả: author / 123456'),
                        const Text('Người xem: reader / 123456'),
                      ]))))),
    ),
  );
}

class HomePage extends StatefulWidget {
  final Map<String, Object?> user;
  const HomePage({super.key, required this.user});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final search = TextEditingController();
  String selectedCategory = 'Tất cả';
  List<Map<String, Object?>> stories = [];
  late Map<String, Object?> user;
  int tabIndex = 0;
  int pendingCount = 0;
  bool get isAdmin => user['role'] == 'Admin';
  bool get isAuthor => user['role'] == 'Author';
  int get userId => user['id'] as int;
  int get panelIndex => 2; // tab thứ 3: Duyệt (admin) hoặc Tác giả

  @override
  void initState() {
    super.initState();
    user = widget.user;
    loadStories();
  }

  Future<void> refreshUser() async {
    final u = await DB.getUser(userId);
    if (u != null && mounted) {
      setState(() {
        user = u;
        if (!isAdmin && !isAuthor && tabIndex == panelIndex) tabIndex = 0;
      });
    }
  }

  Future<void> loadStories() async {
    await refreshUser();
    if (isAdmin) pendingCount = await DB.pendingTotal();
    if (tabIndex == panelIndex) {
      if (mounted) setState(() {});
      return;
    }
    final all = tabIndex == 1 ? await DB.getFavorites(userId) : await DB.getStories();
    final q = search.text.toLowerCase();
    final filtered = all.where((s) {
      final title = (s['title'] as String? ?? '').toLowerCase();
      final author = (s['author'] as String? ?? '').toLowerCase();
      final matchText = title.contains(q) || author.contains(q);
      final matchCategory = selectedCategory == 'Tất cả' || s['category'] == selectedCategory;
      return matchText && matchCategory;
    }).toList();
    if (mounted) setState(() => stories = filtered);
  }

  Future<void> openDetail(Map<String, Object?> story) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => StoryDetailPage(story: story, user: user)));
    loadStories();
  }

  void snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // Chỉ Admin dùng ở trang chủ. Tác giả dùng panel riêng.
  Future<void> editStory([Map<String, Object?>? story]) async {
    final v = await showStoryEditor(context, story: story);
    if (v == null) return;
    final ok = await DB.saveStory(userId, v, storyId: story?['id'] as int?);
    if (!ok) snack('Bạn không có quyền thực hiện thao tác này');
    await loadStories();
  }

  Future<void> deleteStory(Map<String, Object?> story) async {
    if (!await confirmDialog(context, 'Xóa truyện', 'Bạn muốn xóa "${story['title']}"?', 'Xóa')) return;
    final ok = await DB.deleteStory(userId, story['id'] as int);
    if (!ok) snack('Bạn không có quyền xóa truyện này');
    await loadStories();
  }

  void logout() {
    Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const LoginPage()), (route) => false);
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  String get appBarTitle {
    if (tabIndex == 1) return 'Truyện yêu thích';
    if (tabIndex == panelIndex) return isAdmin ? 'Quản trị - Duyệt' : 'Góc tác giả';
    return 'TRUYỆN MỘC';
  }

  Widget buildPanel() => isAdmin
      ? AdminPanel(user: user, onChanged: loadStories)
      : AuthorPanel(user: user, onChanged: loadStories);

  @override
  Widget build(BuildContext context) {
    final destinations = <NavigationDestination>[
      const NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Trang chủ'),
      const NavigationDestination(icon: Icon(Icons.favorite_border), selectedIcon: Icon(Icons.favorite), label: 'Yêu thích'),
      if (isAdmin)
        NavigationDestination(
            icon: Badge(label: Text('$pendingCount'), isLabelVisible: pendingCount > 0, child: const Icon(Icons.fact_check_outlined)),
            selectedIcon: const Icon(Icons.fact_check),
            label: 'Duyệt'),
      if (isAuthor) const NavigationDestination(icon: Icon(Icons.edit_note_outlined), selectedIcon: Icon(Icons.edit_note), label: 'Tác giả'),
    ];
    return Scaffold(
      appBar: AppBar(
          backgroundColor: const Color(0xFF30235F),
          foregroundColor: Colors.white,
          title: Text(appBarTitle, style: const TextStyle(fontWeight: FontWeight.bold)),
          actions: [
            if (isAdmin && tabIndex == 0) IconButton(onPressed: () => editStory(), icon: const Icon(Icons.add), tooltip: 'Thêm truyện'),
            IconButton(onPressed: () => showProfile(), icon: const Icon(Icons.account_circle_outlined), tooltip: 'Tài khoản'),
          ]),
      body: tabIndex == panelIndex && (isAdmin || isAuthor) ? buildPanel() : buildHomeBody(),
      bottomNavigationBar: NavigationBar(
          selectedIndex: tabIndex < destinations.length ? tabIndex : 0,
          onDestinationSelected: (v) {
            setState(() => tabIndex = v);
            loadStories();
          },
          destinations: destinations),
    );
  }

  Widget buildHomeBody() => Column(children: [
    Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
        child: TextField(
            controller: search,
            onChanged: (_) => loadStories(),
            decoration: InputDecoration(
                hintText: 'Tìm truyện hoặc tác giả...',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none)))),
    if (tabIndex == 0)
      SizedBox(
          height: 44,
          child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              children: kCategories
                  .map((c) => Padding(
                  padding: const EdgeInsets.only(right: 7),
                  child: ChoiceChip(
                      label: Text(c),
                      selected: selectedCategory == c,
                      onSelected: (_) {
                        setState(() => selectedCategory = c);
                        loadStories();
                      })))
                  .toList())),
    if (tabIndex == 0)
      Container(
          width: double.infinity,
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), gradient: const LinearGradient(colors: [Color(0xFF30235F), Color(0xFF7657D1)])),
          child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('TRUYỆN ĐỀ CỬ', style: TextStyle(color: Colors.white70, fontSize: 12)),
            SizedBox(height: 6),
            Text('Khám phá những câu chuyện nổi bật', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold))
          ])),
    Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Align(alignment: Alignment.centerLeft, child: Text(tabIndex == 1 ? 'Danh sách yêu thích' : 'Danh sách truyện', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)))),
    Expanded(
        child: stories.isEmpty
            ? const Center(child: Text('Chưa có truyện phù hợp'))
            : GridView.builder(
            padding: const EdgeInsets.all(12),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, childAspectRatio: .66, crossAxisSpacing: 12, mainAxisSpacing: 12),
            itemCount: stories.length,
            itemBuilder: (ctx, i) {
              final s = stories[i];
              return InkWell(
                  onTap: () => openDetail(s),
                  borderRadius: BorderRadius.circular(14),
                  child: Card(
                      clipBehavior: Clip.antiAlias,
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Expanded(
                            child: Stack(fit: StackFit.expand, children: [
                              _buildStoryThumbnail(s),
                              if (s['hot'] == 1)
                                const Positioned(
                                    top: 7,
                                    right: 7,
                                    child: Chip(label: Text('HOT', style: TextStyle(color: Colors.white, fontSize: 10)), backgroundColor: Colors.deepOrange, visualDensity: VisualDensity.compact)),
                            ])),
                        Padding(padding: const EdgeInsets.fromLTRB(9, 8, 9, 2), child: Text(s['title'] as String, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold))),
                        Padding(padding: const EdgeInsets.symmetric(horizontal: 9), child: Text(s['author'] as String? ?? '', maxLines: 1, style: const TextStyle(fontSize: 12, color: Colors.grey))),
                        Padding(padding: const EdgeInsets.fromLTRB(9, 2, 9, 0), child: Text(s['category'] as String, maxLines: 1, style: const TextStyle(fontSize: 12, color: Color(0xFF6044B8)))),
                        if (isAdmin && tabIndex == 0)
                          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                            IconButton(visualDensity: VisualDensity.compact, onPressed: () => editStory(s), icon: const Icon(Icons.edit_outlined, size: 18)),
                            IconButton(visualDensity: VisualDensity.compact, onPressed: () => deleteStory(s), icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red))
                          ])
                        else
                          const SizedBox(height: 8),
                      ])));
            })),
  ]);

  Widget _buildStoryThumbnail(Map<String, Object?> story) {
    final imageUrl = (story['image_url'] as String? ?? '').trim();
    final hot = story['hot'] == 1;
    final fallback = Container(
      width: double.infinity,
      decoration: BoxDecoration(
          gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: hot ? [const Color(0xFFB84B79), const Color(0xFF30235F)] : [const Color(0xFF458B91), const Color(0xFF30235F)])),
      child: const Center(child: Icon(Icons.auto_stories, size: 62, color: Colors.white70)),
    );
    if (imageUrl.isEmpty) return fallback;
    return Image.network(imageUrl, fit: BoxFit.cover, width: double.infinity, errorBuilder: (context, error, stackTrace) => fallback, loadingBuilder: (context, child, progress) {
      if (progress == null) return child;
      return fallback;
    });
  }

  Future<void> showProfile() async {
    await refreshUser();
    final req = isAdmin ? null : await DB.getMyRequest(userId);
    if (!mounted) return;
    final isReader = user['role'] == 'Reader';
    final reqStatus = req?['status'] as String?;
    showModalBottomSheet(
        context: context,
        showDragHandle: true,
        builder: (ctx) => Padding(
            padding: const EdgeInsets.all(22),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              CircleAvatar(radius: 32, child: Icon(isAdmin ? Icons.admin_panel_settings : isAuthor ? Icons.edit_note : Icons.person, size: 34)),
              const SizedBox(height: 12),
              Text(user['username'] as String, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              Text('Vai trò: ${roleLabel(user['role'] as String?)}'),
              if (isAuthor && (user['pen_name'] as String? ?? '').isNotEmpty) Text('Bút danh: ${user['pen_name']}'),
              const SizedBox(height: 14),
              if (isReader && reqStatus == kPending)
                const Text('Yêu cầu làm tác giả của bạn đang chờ admin duyệt.', textAlign: TextAlign.center, style: TextStyle(color: Colors.orange)),
              if (isReader && reqStatus == kRejected) const Padding(padding: EdgeInsets.only(bottom: 8), child: Text('Yêu cầu trước của bạn đã bị từ chối.', style: TextStyle(color: Colors.red))),
              if (isReader && reqStatus != kPending)
                SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(ctx);
                          requestAuthor();
                        },
                        icon: const Icon(Icons.edit_note),
                        label: Text(reqStatus == kRejected ? 'Gửi lại yêu cầu làm tác giả' : 'Xin làm tác giả'))),
              const SizedBox(height: 10),
              SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        logout();
                      },
                      icon: const Icon(Icons.logout),
                      label: const Text('Đăng xuất'))),
              const SizedBox(height: 10)
            ])));
  }

  Future<void> requestAuthor() async {
    final pen = TextEditingController();
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Xin làm tác giả'),
          content: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(controller: pen, decoration: const InputDecoration(labelText: 'Bút danh')),
                TextField(controller: reason, maxLines: 4, decoration: const InputDecoration(labelText: 'Giới thiệu bản thân / lý do', alignLabelWithHint: true)),
                const SizedBox(height: 8),
                Text('Thu nhập tạm tính: ${money(kRatePerView)} / lượt xem (mỗi người đọc tính 1 lượt/ngày).', style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ])),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Gửi yêu cầu')),
          ],
        ));
    final penName = pen.text.trim();
    final why = reason.text.trim();
    pen.dispose();
    reason.dispose();
    if (ok != true) return;
    if (penName.isEmpty) {
      snack('Vui lòng nhập bút danh');
      return;
    }
    final sent = await DB.submitAuthorRequest(userId, penName, why);
    snack(sent ? 'Đã gửi yêu cầu, vui lòng chờ admin duyệt' : 'Không thể gửi yêu cầu (đang chờ duyệt hoặc đã là tác giả)');
  }
}

// ======================= PANEL TÁC GIẢ =======================
class AuthorPanel extends StatefulWidget {
  final Map<String, Object?> user;
  final VoidCallback onChanged;
  const AuthorPanel({super.key, required this.user, required this.onChanged});
  @override
  State<AuthorPanel> createState() => _AuthorPanelState();
}

class _AuthorPanelState extends State<AuthorPanel> {
  List<Map<String, Object?>> mine = [];
  int get uid => widget.user['id'] as int;
  String get penName {
    final pen = (widget.user['pen_name'] as String? ?? '').trim();
    return pen.isEmpty ? widget.user['username'] as String : pen;
  }

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final r = await DB.getOwnStories(uid);
    if (mounted) setState(() => mine = r);
  }

  void snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> edit([Map<String, Object?>? story]) async {
    final v = await showStoryEditor(context, story: story, lockedAuthor: penName, allowHot: false);
    if (v == null) return;
    final ok = await DB.saveStory(uid, v, storyId: story?['id'] as int?);
    snack(ok ? 'Đã gửi truyện cho admin xét duyệt' : 'Bạn không có quyền thực hiện thao tác này');
    await load();
    widget.onChanged();
  }

  Future<void> remove(Map<String, Object?> s) async {
    if (!await confirmDialog(context, 'Xóa truyện', 'Bạn muốn xóa "${s['title']}"?', 'Xóa')) return;
    final ok = await DB.deleteStory(uid, s['id'] as int);
    if (!ok) snack('Bạn không có quyền xóa truyện này');
    await load();
    widget.onChanged();
  }

  Color statusColor(String st) => st == kApproved ? Colors.green : st == kRejected ? Colors.red : Colors.orange;

  @override
  Widget build(BuildContext context) {
    final totalViews = mine.where((s) => s['approval'] == kApproved).fold<int>(0, (a, s) => a + ((s['views'] as int?) ?? 0));
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(onPressed: () => edit(), icon: const Icon(Icons.upload), label: const Text('Đăng truyện')),
      body: ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 90), children: [
        Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), gradient: const LinearGradient(colors: [Color(0xFF30235F), Color(0xFF7657D1)])),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Bút danh: $penName', style: const TextStyle(color: Colors.white70)),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: _stat('Lượt xem', '$totalViews')),
                Expanded(child: _stat('Thu nhập tạm tính', money(totalViews * kRatePerView))),
              ]),
              const SizedBox(height: 8),
              Text('${money(kRatePerView)} / lượt xem · mỗi người đọc tính 1 lượt/ngày · chỉ tính truyện đã duyệt',
                  style: const TextStyle(color: Colors.white60, fontSize: 11)),
            ])),
        const SizedBox(height: 16),
        const Text('Truyện của tôi', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        if (mine.isEmpty) const Padding(padding: EdgeInsets.all(30), child: Center(child: Text('Bạn chưa đăng truyện nào.\nBấm "Đăng truyện" để bắt đầu.', textAlign: TextAlign.center))),
        for (final s in mine)
          Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Card(
                  child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Expanded(child: Text(s['title'] as String, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
                          Chip(
                              label: Text(s['approval'] as String? ?? kApproved, style: const TextStyle(color: Colors.white, fontSize: 11)),
                              backgroundColor: statusColor(s['approval'] as String? ?? kApproved),
                              visualDensity: VisualDensity.compact),
                        ]),
                        Text('${s['category']} · ${s['status']}', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                        const SizedBox(height: 6),
                        Text('${(s['views'] as int?) ?? 0} lượt xem · ${money(((s['views'] as int?) ?? 0) * kRatePerView)}', style: const TextStyle(fontWeight: FontWeight.w600)),
                        if (s['approval'] == kRejected && (s['reject_reason'] as String? ?? '').isNotEmpty)
                          Padding(padding: const EdgeInsets.only(top: 6), child: Text('Lý do từ chối: ${s['reject_reason']}', style: const TextStyle(color: Colors.red))),
                        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                          TextButton.icon(
                              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ReadingPage(title: s['title'] as String, author: s['author'] as String? ?? '', content: s['content'] as String? ?? ''))),
                              icon: const Icon(Icons.menu_book, size: 18),
                              label: const Text('Xem')),
                          TextButton.icon(onPressed: () => edit(s), icon: const Icon(Icons.edit_outlined, size: 18), label: const Text('Sửa')),
                          TextButton.icon(onPressed: () => remove(s), icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red), label: const Text('Xóa', style: TextStyle(color: Colors.red))),
                        ]),
                      ])))),
      ]),
    );
  }

  Widget _stat(String label, String value) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
    Text(value, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
  ]);
}

// ======================= PANEL ADMIN DUYỆT =======================
class AdminPanel extends StatefulWidget {
  final Map<String, Object?> user;
  final VoidCallback onChanged;
  const AdminPanel({super.key, required this.user, required this.onChanged});
  @override
  State<AdminPanel> createState() => _AdminPanelState();
}

class _AdminPanelState extends State<AdminPanel> {
  List<Map<String, Object?>> pendingStories = [];
  List<Map<String, Object?>> pendingRequests = [];
  int get uid => widget.user['id'] as int;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final a = await DB.getPendingStories();
    final b = await DB.getPendingRequests();
    if (mounted) {
      setState(() {
        pendingStories = a;
        pendingRequests = b;
      });
    }
  }

  void snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> approveStory(Map<String, Object?> s) async {
    final ok = await DB.reviewStory(uid, s['id'] as int, true);
    snack(ok ? 'Đã duyệt "${s['title']}"' : 'Bạn không có quyền duyệt');
    await load();
    widget.onChanged();
  }

  Future<void> rejectStory(Map<String, Object?> s) async {
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Từ chối truyện'),
          content: TextField(controller: reason, maxLines: 3, decoration: const InputDecoration(labelText: 'Lý do (tác giả sẽ thấy)')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Từ chối')),
          ],
        ));
    final text = reason.text.trim();
    reason.dispose();
    if (ok != true) return;
    await DB.reviewStory(uid, s['id'] as int, false, text);
    await load();
    widget.onChanged();
  }

  Future<void> reviewRequest(Map<String, Object?> r, bool approve) async {
    final ok = await DB.reviewRequest(uid, r['id'] as int, approve);
    snack(ok ? (approve ? 'Đã cấp quyền tác giả cho ${r['username']}' : 'Đã từ chối yêu cầu') : 'Bạn không có quyền duyệt');
    await load();
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    child: Column(children: [
      Material(
          color: Colors.white,
          child: TabBar(tabs: [
            Tab(text: 'Truyện chờ duyệt (${pendingStories.length})'),
            Tab(text: 'Yêu cầu tác giả (${pendingRequests.length})'),
          ])),
      Expanded(child: TabBarView(children: [storiesTab(), requestsTab()])),
    ]),
  );

  Widget storiesTab() {
    if (pendingStories.isEmpty) return const Center(child: Text('Không có truyện nào chờ duyệt'));
    return ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: pendingStories.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (ctx, i) {
          final s = pendingStories[i];
          return Card(
              child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(s['title'] as String, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text('Tác giả: ${s['author']} · ${s['category']} · ${s['status']}', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                    const SizedBox(height: 8),
                    Text((s['description'] as String? ?? '').isEmpty ? '(Chưa có mô tả)' : s['description'] as String, maxLines: 3, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 6),
                    Wrap(alignment: WrapAlignment.end, spacing: 6, children: [
                      TextButton.icon(
                          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ReadingPage(title: s['title'] as String, author: s['author'] as String? ?? '', content: s['content'] as String? ?? ''))),
                          icon: const Icon(Icons.menu_book, size: 18),
                          label: const Text('Đọc thử')),
                      TextButton(onPressed: () => rejectStory(s), child: const Text('Từ chối', style: TextStyle(color: Colors.red))),
                      FilledButton(onPressed: () => approveStory(s), child: const Text('Duyệt')),
                    ]),
                  ])));
        });
  }

  Widget requestsTab() {
    if (pendingRequests.isEmpty) return const Center(child: Text('Không có yêu cầu nào'));
    return ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: pendingRequests.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (ctx, i) {
          final r = pendingRequests[i];
          return Card(
              child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Bút danh: ${r['pen_name']}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    Text('Tài khoản: ${r['username']}', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                    const SizedBox(height: 8),
                    Text((r['reason'] as String? ?? '').isEmpty ? '(Không ghi lý do)' : r['reason'] as String),
                    const SizedBox(height: 6),
                    Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                      TextButton(onPressed: () => reviewRequest(r, false), child: const Text('Từ chối', style: TextStyle(color: Colors.red))),
                      const SizedBox(width: 6),
                      FilledButton(onPressed: () => reviewRequest(r, true), child: const Text('Cấp quyền tác giả')),
                    ]),
                  ])));
        });
  }
}

class ReadingPage extends StatelessWidget {
  final String title;
  final String author;
  final String content;
  const ReadingPage({super.key, required this.title, required this.author, required this.content});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Đọc truyện')),
    body: content.trim().isEmpty
        ? const Center(
        child: Padding(
            padding: EdgeInsets.all(24),
            child: Text('Truyện này chưa có nội dung.', textAlign: TextAlign.center, style: TextStyle(fontSize: 16, height: 1.6))))
        : SelectionArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 24, 22, 40),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontSize: 25, fontWeight: FontWeight.bold, height: 1.3)),
            const SizedBox(height: 8),
            Text('Tác giả: $author', style: const TextStyle(color: Colors.grey, fontSize: 14)),
            const Divider(height: 30),
            Text(content, style: const TextStyle(fontSize: 18, height: 1.9, letterSpacing: .2)),
            const SizedBox(height: 30),
            const Center(child: Text('— Hết —', style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic))),
          ]),
        )),
  );
}

class StoryDetailPage extends StatefulWidget {
  final Map<String, Object?> story;
  final Map<String, Object?> user;
  const StoryDetailPage({super.key, required this.story, required this.user});
  @override
  State<StoryDetailPage> createState() => _StoryDetailPageState();
}

class _StoryDetailPageState extends State<StoryDetailPage> {
  bool favorite = false;
  bool showFullDescription = false;
  int myRating = 0;
  double averageRating = 0;
  int ratingCount = 0;
  int views = 0;
  List<Map<String, Object?>> related = [];
  int get userId => widget.user['id'] as int;
  int get storyId => widget.story['id'] as int;

  @override
  void initState() {
    super.initState();
    loadDetailData();
  }

  Future<void> loadDetailData() async {
    final fav = await DB.isFavorite(userId, storyId);
    final mine = await DB.db.query('ratings', where: 'user_id=? AND story_id=?', whereArgs: [userId, storyId], limit: 1);
    final stats = await DB.db.rawQuery('SELECT AVG(stars) AS avg_star, COUNT(*) AS total FROM ratings WHERE story_id=?', [storyId]);
    final st = await DB.db.query('stories', columns: ['views'], where: 'id=?', whereArgs: [storyId], limit: 1);
    final category = widget.story['category'];
    final suggestions = await DB.db.query('stories', where: 'category=? AND id<>? AND approval=?', whereArgs: [category, storyId, kApproved], orderBy: 'hot DESC', limit: 4);
    if (!mounted) return;
    setState(() {
      favorite = fav;
      myRating = mine.isEmpty ? 0 : (mine.first['stars'] as int);
      averageRating = (stats.first['avg_star'] as num?)?.toDouble() ?? 0;
      ratingCount = (stats.first['total'] as int?) ?? 0;
      views = st.isEmpty ? 0 : ((st.first['views'] as int?) ?? 0);
      related = suggestions;
    });
  }

  Future<void> toggleFavorite() async {
    await DB.toggleFavorite(userId, storyId);
    await loadDetailData();
  }

  Future<void> rate(int stars) async {
    await DB.db.insert('ratings', {'user_id': userId, 'story_id': storyId, 'stars': stars}, conflictAlgorithm: ConflictAlgorithm.replace);
    await loadDetailData();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã lưu đánh giá của bạn')));
  }

  Future<void> startReading() async {
    final s = widget.story;
    await DB.registerView(userId, storyId); // ghi nhận lượt xem để tính thu nhập tác giả
    if (!mounted) return;
    await Navigator.push(context, MaterialPageRoute(builder: (_) => ReadingPage(title: s['title'] as String, author: s['author'] as String? ?? '', content: s['content'] as String? ?? '')));
    loadDetailData();
  }

  Widget buildCover(Map<String, Object?> story, {double height = 250}) {
    final hot = story['hot'] == 1;
    final imageUrl = (story['image_url'] as String? ?? '').trim();
    final fallback = Container(
      height: height,
      width: double.infinity,
      decoration: BoxDecoration(
          gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: hot ? [const Color(0xFFB84B79), const Color(0xFF30235F)] : [const Color(0xFF458B91), const Color(0xFF30235F)])),
      child: Stack(children: [
        Positioned(right: -18, top: -25, child: Icon(Icons.auto_stories, size: 190, color: Colors.white.withValues(alpha: .10))),
        Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.menu_book_rounded, size: 76, color: Colors.white70),
              const SizedBox(height: 12),
              Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 25),
                  child: Text(story['title'] as String, textAlign: TextAlign.center, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold))),
            ])),
      ]),
    );
    Widget cover = fallback;
    if (imageUrl.isNotEmpty) {
      cover = Image.network(imageUrl, height: height, width: double.infinity, fit: BoxFit.cover, errorBuilder: (context, error, stackTrace) => fallback, loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return fallback;
      });
    }
    return SizedBox(
        height: height,
        width: double.infinity,
        child: Stack(fit: StackFit.expand, children: [
          cover,
          if (hot) const Positioned(top: 16, right: 16, child: Chip(label: Text('HOT', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), backgroundColor: Colors.deepOrange)),
        ]));
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.story;
    final description = (s['description'] as String?) ?? '';
    return Scaffold(
      appBar: AppBar(title: const Text('Chi tiết truyện'), actions: [
        IconButton(tooltip: 'Yêu thích', onPressed: toggleFavorite, icon: Icon(favorite ? Icons.favorite : Icons.favorite_border, color: favorite ? Colors.red : null)),
      ]),
      body: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            buildCover(s),
            Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(s['title'] as String, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, height: 1.2)),
                  const SizedBox(height: 8),
                  Row(children: [
                    const Icon(Icons.person_outline, size: 18, color: Colors.grey),
                    const SizedBox(width: 6),
                    Expanded(child: Text(s['author'] as String? ?? 'Chưa rõ tác giả', style: const TextStyle(color: Colors.grey, fontSize: 15)))
                  ]),
                  const SizedBox(height: 14),
                  Wrap(spacing: 8, runSpacing: 4, children: [
                    Chip(avatar: const Icon(Icons.category_outlined, size: 16), label: Text(s['category'] as String? ?? 'Khác')),
                    Chip(avatar: const Icon(Icons.bookmark_outline, size: 16), label: Text(s['status'] as String? ?? 'Đang cập nhật')),
                    Chip(avatar: const Icon(Icons.visibility_outlined, size: 16), label: Text('$views lượt xem')),
                  ]),
                  const SizedBox(height: 12),
                  Card(
                      child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Row(children: [
                            const Icon(Icons.star_rounded, color: Colors.amber, size: 30),
                            const SizedBox(width: 8),
                            Text(ratingCount == 0 ? 'Chưa có đánh giá' : averageRating.toStringAsFixed(1), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                            const SizedBox(width: 8),
                            Expanded(child: Text(ratingCount == 0 ? 'Hãy là người đánh giá đầu tiên' : '$ratingCount lượt đánh giá', style: const TextStyle(color: Colors.grey))),
                          ]))),
                  const SizedBox(height: 22),
                  const Text('Giới thiệu truyện', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 9),
                  Text(description.isEmpty ? 'Chưa có mô tả cho truyện này.' : description,
                      maxLines: showFullDescription ? null : 5, overflow: showFullDescription ? TextOverflow.visible : TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, height: 1.65)),
                  if (description.length > 180)
                    Align(alignment: Alignment.centerLeft, child: TextButton(onPressed: () => setState(() => showFullDescription = !showFullDescription), child: Text(showFullDescription ? 'Thu gọn' : 'Xem thêm'))),
                  const SizedBox(height: 16),
                  SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: startReading, icon: const Icon(Icons.menu_book), label: const Text('ĐỌC TRUYỆN'))),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(onPressed: toggleFavorite, icon: Icon(favorite ? Icons.favorite : Icons.favorite_border), label: Text(favorite ? 'Đã thêm vào yêu thích' : 'Thêm vào yêu thích')),
                  const SizedBox(height: 26),
                  const Text('Đánh giá của bạn', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Row(children: List.generate(5, (index) => IconButton(onPressed: () => rate(index + 1), icon: Icon(index < myRating ? Icons.star : Icons.star_border, color: Colors.amber, size: 34)))),
                  Text(myRating == 0 ? 'Chọn số sao để đánh giá truyện' : 'Bạn đã đánh giá $myRating/5 sao', style: const TextStyle(color: Colors.grey)),
                  if (related.isNotEmpty) ...[
                    const SizedBox(height: 28),
                    const Text('Truyện cùng thể loại', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    SizedBox(
                        height: 190,
                        child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: related.length,
                            separatorBuilder: (_, __) => const SizedBox(width: 12),
                            itemBuilder: (ctx, index) {
                              final item = related[index];
                              return SizedBox(
                                  width: 135,
                                  child: InkWell(
                                      borderRadius: BorderRadius.circular(12),
                                      onTap: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => StoryDetailPage(story: item, user: widget.user))),
                                      child: Card(
                                          clipBehavior: Clip.antiAlias,
                                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                            Expanded(child: buildCover(item, height: 120)),
                                            Padding(padding: const EdgeInsets.all(8), child: Text(item['title'] as String, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold))),
                                          ]))));
                            })),
                  ],
                ])),
          ])),
    );
  }
}