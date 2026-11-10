import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;

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
      version: 5,
      onCreate: (db, version) async {
        await db.execute('''CREATE TABLE users(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          username TEXT, password TEXT, role TEXT)''');
        await db.execute('''CREATE TABLE stories(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          title TEXT, author TEXT, category TEXT, hot INTEGER,
          description TEXT DEFAULT '', status TEXT DEFAULT 'Đang cập nhật', image_url TEXT DEFAULT '', content TEXT DEFAULT '')''');
        await db.execute('''CREATE TABLE favorites(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          user_id INTEGER NOT NULL, story_id INTEGER NOT NULL,
          UNIQUE(user_id, story_id))''');
        await db.execute('''CREATE TABLE ratings(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          user_id INTEGER NOT NULL, story_id INTEGER NOT NULL,
          stars INTEGER NOT NULL CHECK(stars BETWEEN 1 AND 5),
          UNIQUE(user_id, story_id))''');
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
      },
    );
  }

  static Future<void> seed(Database db) async {
    await db.insert('users', {'username':'admin','password':'123456','role':'Admin'});
    await db.insert('users', {'username':'reader','password':'123456','role':'Reader'});
    final samples = [
      ['Kiếm Sĩ Bình Minh','Lam Phong','Hành động',1,'Một kiếm sĩ trẻ bắt đầu hành trình tìm lại ánh sáng cho vương quốc.','Đang cập nhật'],
      ['Thế Giới Phép Thuật','Mộc Miên','Fantasy',1,'Một thế giới nơi phép thuật và những bí mật cổ xưa cùng tồn tại.','Đang cập nhật'],
      ['Mùa Hạ Có Cậu','An Nhiên','Tình cảm',0,'Câu chuyện nhẹ nhàng về tình bạn và những rung động đầu đời.','Đã hoàn thành'],
      ['Đầu Bếp Vạn Năng','Bếp Nhỏ','Hài hước',0,'Những tình huống dở khóc dở cười trong căn bếp đặc biệt.','Đang cập nhật'],
      ['Bản Đồ Bí Ẩn','Hải Đăng','Phiêu lưu',1,'Nhóm bạn lên đường giải mã tấm bản đồ bí ẩn.','Đang cập nhật'],
    ];
    for (final s in samples) {
      await db.insert('stories', {'title':s[0],'author':s[1],'category':s[2],'hot':s[3],'description':s[4],'status':s[5]});
    }
  }

  static Future<List<Map<String,Object?>>> getStories() => db.query('stories', orderBy:'hot DESC, title ASC');
  static Future<bool> isFavorite(int userId, int storyId) async {
    final rows = await db.query('favorites', where:'user_id=? AND story_id=?', whereArgs:[userId,storyId]);
    return rows.isNotEmpty;
  }
  static Future<void> toggleFavorite(int userId, int storyId) async {
    final exists = await isFavorite(userId, storyId);
    if (exists) {
      await db.delete('favorites', where:'user_id=? AND story_id=?', whereArgs:[userId,storyId]);
    } else {
      await db.insert('favorites', {'user_id':userId,'story_id':storyId}, conflictAlgorithm:ConflictAlgorithm.ignore);
    }
  }
  static Future<List<Map<String,Object?>>> getFavorites(int userId) async {
    return db.rawQuery('''SELECT stories.* FROM stories
      INNER JOIN favorites ON stories.id=favorites.story_id
      WHERE favorites.user_id=? ORDER BY stories.title''',[userId]);
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner:false,
    title:'Truyện Mộc',
    theme:ThemeData(useMaterial3:true,colorSchemeSeed:const Color(0xFF6044B8),scaffoldBackgroundColor:const Color(0xFFF7F6FA),cardTheme:const CardThemeData(elevation:2,margin:EdgeInsets.zero)),
    home:const LoginPage(),
  );
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState()=>_LoginPageState();
}
class _LoginPageState extends State<LoginPage> {
  final username=TextEditingController();
  final password=TextEditingController();
  bool hidePassword=true;
  Future<void> login() async {
    final result=await DB.db.query('users',where:'username=? AND password=?',whereArgs:[username.text.trim(),password.text]);
    if (!mounted) return;
    if (result.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Sai tài khoản hoặc mật khẩu')));
      return;
    }
    Navigator.pushReplacement(context,MaterialPageRoute(builder:(_)=>HomePage(user:result.first)));
  }
  @override
  void dispose(){username.dispose();password.dispose();super.dispose();}
  @override
  Widget build(BuildContext context)=>Scaffold(
    body:Container(
      decoration:const BoxDecoration(gradient:LinearGradient(begin:Alignment.topLeft,end:Alignment.bottomRight,colors:[Color(0xFFECE6FF),Color(0xFFF9F7FF),Color(0xFFE3F0F1)])),
      child:Center(child:SingleChildScrollView(padding:const EdgeInsets.all(24),child:Card(shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(24)),child:Padding(padding:const EdgeInsets.all(24),child:Column(mainAxisSize:MainAxisSize.min,children:[
        const CircleAvatar(radius:38,backgroundColor:Color(0xFFEAE3FF),child:Icon(Icons.auto_stories,size:42,color:Color(0xFF6044B8))),
        const SizedBox(height:12),const Text('TRUYỆN MỘC',style:TextStyle(fontSize:27,fontWeight:FontWeight.bold,letterSpacing:1)),
        const Text('Thế giới truyện dành cho bạn',style:TextStyle(color:Colors.grey)),const SizedBox(height:26),
        TextField(controller:username,decoration:const InputDecoration(labelText:'Tên đăng nhập',prefixIcon:Icon(Icons.person_outline),border:OutlineInputBorder())),const SizedBox(height:14),
        TextField(controller:password,obscureText:hidePassword,decoration:InputDecoration(labelText:'Mật khẩu',prefixIcon:const Icon(Icons.lock_outline),border:const OutlineInputBorder(),suffixIcon:IconButton(icon:Icon(hidePassword?Icons.visibility:Icons.visibility_off),onPressed:()=>setState(()=>hidePassword=!hidePassword)))),const SizedBox(height:20),
        SizedBox(width:double.infinity,child:FilledButton.icon(onPressed:login,icon:const Icon(Icons.login),label:const Padding(padding:EdgeInsets.all(12),child:Text('ĐĂNG NHẬP')))),const SizedBox(height:16),
        const Text('Admin: admin / 123456'),const Text('Người xem: reader / 123456'),
      ]))))),
    ),
  );
}

class HomePage extends StatefulWidget {
  final Map<String,Object?> user;
  const HomePage({super.key,required this.user});
  @override
  State<HomePage> createState()=>_HomePageState();
}
class _HomePageState extends State<HomePage> {
  final search=TextEditingController();
  final categories=['Tất cả','Hành động','Fantasy','Tình cảm','Hài hước','Phiêu lưu'];
  String selectedCategory='Tất cả';
  List<Map<String,Object?>> stories=[];
  int tabIndex=0;
  bool get isAdmin=>widget.user['role']=='Admin';
  int get userId=>widget.user['id'] as int;
  @override
  void initState(){super.initState();loadStories();}
  Future<void> loadStories() async {
    final all=tabIndex==1?await DB.getFavorites(userId):await DB.getStories();
    final q=search.text.toLowerCase();
    final filtered=all.where((s){
      final title=(s['title'] as String? ?? '').toLowerCase();
      final author=(s['author'] as String? ?? '').toLowerCase();
      final matchText=title.contains(q)||author.contains(q);
      final matchCategory=selectedCategory=='Tất cả'||s['category']==selectedCategory;
      return matchText&&matchCategory;
    }).toList();
    if(mounted)setState(()=>stories=filtered);
  }
  Future<void> openDetail(Map<String,Object?> story) async {
    await Navigator.push(context,MaterialPageRoute(builder:(_)=>StoryDetailPage(story:story,user:widget.user)));
    loadStories();
  }
  Future<void> editStory([Map<String,Object?>? story]) async {
    final title=TextEditingController(text:story?['title'] as String? ?? '');
    final author=TextEditingController(text:story?['author'] as String? ?? '');
    final description=TextEditingController(text:story?['description'] as String? ?? '');
    final content=TextEditingController(text:story?['content'] as String? ?? '');
    final imageUrl=TextEditingController(text:story?['image_url'] as String? ?? '');
    String category=story?['category'] as String? ?? categories[1];
    String status=story?['status'] as String? ?? 'Đang cập nhật';
    bool hot=story?['hot']==1;
    final saved=await showDialog<bool>(context:context,builder:(ctx)=>StatefulBuilder(builder:(ctx,setDialog)=>AlertDialog(
      title:Text(story==null?'Thêm truyện':'Sửa truyện'),
      content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
        TextField(controller:title,decoration:const InputDecoration(labelText:'Tên truyện')),
        TextField(controller:author,decoration:const InputDecoration(labelText:'Tác giả')),
        TextField(controller:description,maxLines:4,decoration:const InputDecoration(labelText:'Mô tả nội dung')),
        const SizedBox(height:10),
        TextField(controller:content,maxLines:12,minLines:8,decoration:const InputDecoration(labelText:'Nội dung truyện chữ',hintText:'Nhập toàn bộ nội dung truyện tại đây...',alignLabelWithHint:true,border:OutlineInputBorder())),
        TextField(controller:imageUrl,keyboardType:TextInputType.url,decoration:const InputDecoration(labelText:'Đường dẫn ảnh bìa (URL)',hintText:'https://example.com/anh-truyen.jpg',prefixIcon:Icon(Icons.image_outlined))),
        DropdownButtonFormField<String>(value:category,decoration:const InputDecoration(labelText:'Chủ đề'),items:categories.skip(1).map((c)=>DropdownMenuItem(value:c,child:Text(c))).toList(),onChanged:(v){if(v!=null)setDialog(()=>category=v);}),
        DropdownButtonFormField<String>(value:status,decoration:const InputDecoration(labelText:'Trạng thái'),items:['Đang cập nhật','Đã hoàn thành','Tạm ngưng'].map((s)=>DropdownMenuItem(value:s,child:Text(s))).toList(),onChanged:(v){if(v!=null)setDialog(()=>status=v);}),
        SwitchListTile(contentPadding:EdgeInsets.zero,title:const Text('Truyện HOT'),value:hot,onChanged:(v)=>setDialog(()=>hot=v)),
      ])),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Hủy')),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Lưu'))],
    )));
    if(saved==true&&title.text.trim().isNotEmpty){
      final values={'title':title.text.trim(),'author':author.text.trim(),'category':category,'hot':hot?1:0,'description':description.text.trim(),'status':status,'image_url':imageUrl.text.trim(),'content':content.text.trim()};
      if(story==null){await DB.db.insert('stories',values);}else{await DB.db.update('stories',values,where:'id=?',whereArgs:[story['id']]);}
      await loadStories();
    }
    title.dispose();author.dispose();description.dispose();content.dispose();imageUrl.dispose();
  }
  Future<void> deleteStory(Map<String,Object?> story) async {
    final ok=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(title:const Text('Xóa truyện'),content:Text('Bạn muốn xóa "${story['title']}"?'),actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Hủy')),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Xóa'))]));
    if(ok==true){await DB.db.delete('favorites',where:'story_id=?',whereArgs:[story['id']]);await DB.db.delete('stories',where:'id=?',whereArgs:[story['id']]);await loadStories();}
  }
  void logout(){Navigator.pushAndRemoveUntil(context,MaterialPageRoute(builder:(_)=>const LoginPage()),(route)=>false);}
  @override
  void dispose(){search.dispose();super.dispose();}
  @override
  Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(backgroundColor:const Color(0xFF30235F),foregroundColor:Colors.white,title:Text(tabIndex==1?'Truyện yêu thích':'TRUYỆN MỘC',style:const TextStyle(fontWeight:FontWeight.bold)),actions:[if(isAdmin&&tabIndex==0)IconButton(onPressed:()=>editStory(),icon:const Icon(Icons.add),tooltip:'Thêm truyện'),IconButton(onPressed:()=>showProfile(),icon:const Icon(Icons.account_circle_outlined),tooltip:'Tài khoản')]),
    body:Column(children:[
      Padding(padding:const EdgeInsets.fromLTRB(12,12,12,8),child:TextField(controller:search,onChanged:(_)=>loadStories(),decoration:InputDecoration(hintText:'Tìm truyện hoặc tác giả...',prefixIcon:const Icon(Icons.search),filled:true,fillColor:Colors.white,border:OutlineInputBorder(borderRadius:BorderRadius.circular(14),borderSide:BorderSide.none)))),
      if(tabIndex==0)SizedBox(height:44,child:ListView(scrollDirection:Axis.horizontal,padding:const EdgeInsets.symmetric(horizontal:10),children:categories.map((c)=>Padding(padding:const EdgeInsets.only(right:7),child:ChoiceChip(label:Text(c),selected:selectedCategory==c,onSelected:(_){setState(()=>selectedCategory=c);loadStories();}))).toList())),
      if(tabIndex==0)Container(width:double.infinity,margin:const EdgeInsets.all(12),padding:const EdgeInsets.all(18),decoration:BoxDecoration(borderRadius:BorderRadius.circular(18),gradient:const LinearGradient(colors:[Color(0xFF30235F),Color(0xFF7657D1)])),child:const Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text('TRUYỆN ĐỀ CỬ',style:TextStyle(color:Colors.white70,fontSize:12)),SizedBox(height:6),Text('Khám phá những câu chuyện nổi bật',style:TextStyle(color:Colors.white,fontSize:18,fontWeight:FontWeight.bold))])),
      Padding(padding:const EdgeInsets.symmetric(horizontal:16,vertical:6),child:Align(alignment:Alignment.centerLeft,child:Text(tabIndex==1?'Danh sách yêu thích':'Danh sách truyện',style:const TextStyle(fontSize:17,fontWeight:FontWeight.bold)))),
      Expanded(child:stories.isEmpty?const Center(child:Text('Chưa có truyện phù hợp')):GridView.builder(padding:const EdgeInsets.all(12),gridDelegate:const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount:2,childAspectRatio:.66,crossAxisSpacing:12,mainAxisSpacing:12),itemCount:stories.length,itemBuilder:(ctx,i){final s=stories[i];return InkWell(onTap:()=>openDetail(s),borderRadius:BorderRadius.circular(14),child:Card(clipBehavior:Clip.antiAlias,child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Expanded(child:Stack(fit:StackFit.expand,children:[
          _buildStoryThumbnail(s),
          if(s['hot']==1)const Positioned(top:7,right:7,child:Chip(label:Text('HOT',style:TextStyle(color:Colors.white,fontSize:10)),backgroundColor:Colors.deepOrange,visualDensity:VisualDensity.compact)),
        ])),
        Padding(padding:const EdgeInsets.fromLTRB(9,8,9,2),child:Text(s['title'] as String,maxLines:2,overflow:TextOverflow.ellipsis,style:const TextStyle(fontWeight:FontWeight.bold))),
        Padding(padding:const EdgeInsets.symmetric(horizontal:9),child:Text(s['author'] as String? ?? '',maxLines:1,style:const TextStyle(fontSize:12,color:Colors.grey))),
        Padding(padding:const EdgeInsets.fromLTRB(9,2,9,0),child:Text(s['category'] as String,maxLines:1,style:const TextStyle(fontSize:12,color:Color(0xFF6044B8)))),
        if(isAdmin&&tabIndex==0)Row(mainAxisAlignment:MainAxisAlignment.end,children:[IconButton(visualDensity:VisualDensity.compact,onPressed:()=>editStory(s),icon:const Icon(Icons.edit_outlined,size:18)),IconButton(visualDensity:VisualDensity.compact,onPressed:()=>deleteStory(s),icon:const Icon(Icons.delete_outline,size:18,color:Colors.red))])else const SizedBox(height:8),
      ])));})),
    ]),
    bottomNavigationBar:NavigationBar(selectedIndex:tabIndex,onDestinationSelected:(v){setState(()=>tabIndex=v);loadStories();},destinations:const [NavigationDestination(icon:Icon(Icons.home_outlined),selectedIcon:Icon(Icons.home),label:'Trang chủ'),NavigationDestination(icon:Icon(Icons.favorite_border),selectedIcon:Icon(Icons.favorite),label:'Yêu thích')]),
  );
  Widget _buildStoryThumbnail(Map<String,Object?> story){
    final imageUrl=(story['image_url'] as String? ?? '').trim();
    final hot=story['hot']==1;
    final fallback=Container(
      width:double.infinity,
      decoration:BoxDecoration(gradient:LinearGradient(begin:Alignment.topLeft,end:Alignment.bottomRight,colors:hot?[const Color(0xFFB84B79),const Color(0xFF30235F)]:[const Color(0xFF458B91),const Color(0xFF30235F)])),
      child:const Center(child:Icon(Icons.auto_stories,size:62,color:Colors.white70)),
    );
    if(imageUrl.isEmpty)return fallback;
    return Image.network(imageUrl,fit:BoxFit.cover,width:double.infinity,errorBuilder:(context,error,stackTrace)=>fallback,loadingBuilder:(context,child,progress){
      if(progress==null)return child;
      return fallback;
    });
  }

  void showProfile(){showModalBottomSheet(context:context,showDragHandle:true,builder:(ctx)=>Padding(padding:const EdgeInsets.all(22),child:Column(mainAxisSize:MainAxisSize.min,children:[CircleAvatar(radius:32,child:Icon(isAdmin?Icons.admin_panel_settings:Icons.person,size:34)),const SizedBox(height:12),Text(widget.user['username'] as String,style:const TextStyle(fontSize:18,fontWeight:FontWeight.bold)),Text('Vai trò: ${widget.user['role']}'),const SizedBox(height:18),SizedBox(width:double.infinity,child:FilledButton.icon(onPressed:(){Navigator.pop(ctx);logout();},icon:const Icon(Icons.logout),label:const Text('Đăng xuất'))),const SizedBox(height:10)])));}
}

class ReadingPage extends StatelessWidget {
  final String title;
  final String author;
  final String content;
  const ReadingPage({super.key,required this.title,required this.author,required this.content});

  @override
  Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('Đọc truyện')),
    body:content.trim().isEmpty
        ? const Center(child:Padding(padding:EdgeInsets.all(24),child:Text('Truyện này chưa có nội dung. Admin hãy vào Sửa truyện và nhập nội dung truyện chữ.',textAlign:TextAlign.center,style:TextStyle(fontSize:16,height:1.6))))
        : SelectionArea(child:SingleChildScrollView(
      padding:const EdgeInsets.fromLTRB(22,24,22,40),
      child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text(title,style:const TextStyle(fontSize:25,fontWeight:FontWeight.bold,height:1.3)),
        const SizedBox(height:8),
        Text('Tác giả: $author',style:const TextStyle(color:Colors.grey,fontSize:14)),
        const Divider(height:30),
        Text(content,style:const TextStyle(fontSize:18,height:1.9,letterSpacing:.2)),
        const SizedBox(height:30),
        const Center(child:Text('— Hết —',style:TextStyle(color:Colors.grey,fontStyle:FontStyle.italic))),
      ]),
    )),
  );
}

class StoryDetailPage extends StatefulWidget {
  final Map<String,Object?> story;
  final Map<String,Object?> user;
  const StoryDetailPage({super.key,required this.story,required this.user});
  @override
  State<StoryDetailPage> createState()=>_StoryDetailPageState();
}

class _StoryDetailPageState extends State<StoryDetailPage>{
  bool favorite=false;
  bool showFullDescription=false;
  int myRating=0;
  double averageRating=0;
  int ratingCount=0;
  List<Map<String,Object?>> related=[];
  int get userId=>widget.user['id'] as int;
  int get storyId=>widget.story['id'] as int;

  @override
  void initState(){super.initState();loadDetailData();}

  Future<void> loadDetailData() async {
    final fav=await DB.isFavorite(userId,storyId);
    final mine=await DB.db.query('ratings',where:'user_id=? AND story_id=?',whereArgs:[userId,storyId],limit:1);
    final stats=await DB.db.rawQuery('SELECT AVG(stars) AS avg_star, COUNT(*) AS total FROM ratings WHERE story_id=?',[storyId]);
    final category=widget.story['category'];
    final suggestions=await DB.db.query('stories',where:'category=? AND id<>?',whereArgs:[category,storyId],orderBy:'hot DESC',limit:4);
    if(!mounted)return;
    setState((){
      favorite=fav;
      myRating=mine.isEmpty?0:(mine.first['stars'] as int);
      averageRating=(stats.first['avg_star'] as num?)?.toDouble() ?? 0;
      ratingCount=(stats.first['total'] as int?) ?? 0;
      related=suggestions;
    });
  }

  Future<void> toggleFavorite() async {
    await DB.toggleFavorite(userId,storyId);
    await loadDetailData();
  }

  Future<void> rate(int stars) async {
    await DB.db.insert('ratings',{'user_id':userId,'story_id':storyId,'stars':stars},conflictAlgorithm:ConflictAlgorithm.replace);
    await loadDetailData();
    if(!mounted)return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Đã lưu đánh giá của bạn')));
  }

  Widget buildCover(Map<String,Object?> story,{double height=250}) {
    final hot=story['hot']==1;
    final imageUrl=(story['image_url'] as String? ?? '').trim();
    final fallback=Container(
      height:height,width:double.infinity,
      decoration:BoxDecoration(gradient:LinearGradient(begin:Alignment.topLeft,end:Alignment.bottomRight,
          colors:hot?[const Color(0xFFB84B79),const Color(0xFF30235F)]:[const Color(0xFF458B91),const Color(0xFF30235F)])),
      child:Stack(children:[
        Positioned(right:-18,top:-25,child:Icon(Icons.auto_stories,size:190,color:Colors.white.withValues(alpha:.10))),
        Center(child:Column(mainAxisSize:MainAxisSize.min,children:[
          const Icon(Icons.menu_book_rounded,size:76,color:Colors.white70),
          const SizedBox(height:12),
          Padding(padding:const EdgeInsets.symmetric(horizontal:25),child:Text(story['title'] as String,textAlign:TextAlign.center,maxLines:3,overflow:TextOverflow.ellipsis,style:const TextStyle(color:Colors.white,fontSize:22,fontWeight:FontWeight.bold))),
        ])),
      ]),
    );
    Widget cover=fallback;
    if(imageUrl.isNotEmpty){
      cover=Image.network(imageUrl,height:height,width:double.infinity,fit:BoxFit.cover,
          errorBuilder:(context,error,stackTrace)=>fallback,
          loadingBuilder:(context,child,progress){if(progress==null)return child;return fallback;});
    }
    return SizedBox(height:height,width:double.infinity,child:Stack(fit:StackFit.expand,children:[
      cover,
      if(hot)const Positioned(top:16,right:16,child:Chip(label:Text('HOT',style:TextStyle(color:Colors.white,fontWeight:FontWeight.bold)),backgroundColor:Colors.deepOrange)),
    ]));
  }

  @override
  Widget build(BuildContext context){
    final s=widget.story;
    final description=(s['description'] as String?) ?? '';
    return Scaffold(
      appBar:AppBar(title:const Text('Chi tiết truyện'),actions:[
        IconButton(tooltip:'Yêu thích',onPressed:toggleFavorite,icon:Icon(favorite?Icons.favorite:Icons.favorite_border,color:favorite?Colors.red:null)),
      ]),
      body:SingleChildScrollView(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        buildCover(s),
        Padding(padding:const EdgeInsets.fromLTRB(20,20,20,32),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text(s['title'] as String,style:const TextStyle(fontSize:26,fontWeight:FontWeight.bold,height:1.2)),
          const SizedBox(height:8),
          Row(children:[const Icon(Icons.person_outline,size:18,color:Colors.grey),const SizedBox(width:6),Expanded(child:Text(s['author'] as String? ?? 'Chưa rõ tác giả',style:const TextStyle(color:Colors.grey,fontSize:15))) ]),
          const SizedBox(height:14),
          Wrap(spacing:8,runSpacing:4,children:[
            Chip(avatar:const Icon(Icons.category_outlined,size:16),label:Text(s['category'] as String? ?? 'Khác')),
            Chip(avatar:const Icon(Icons.bookmark_outline,size:16),label:Text(s['status'] as String? ?? 'Đang cập nhật')),
          ]),
          const SizedBox(height:12),
          Card(child:Padding(padding:const EdgeInsets.all(14),child:Row(children:[
            const Icon(Icons.star_rounded,color:Colors.amber,size:30),const SizedBox(width:8),
            Text(ratingCount==0?'Chưa có đánh giá':averageRating.toStringAsFixed(1),style:const TextStyle(fontSize:22,fontWeight:FontWeight.bold)),
            const SizedBox(width:8),Expanded(child:Text(ratingCount==0?'Hãy là người đánh giá đầu tiên':'$ratingCount lượt đánh giá',style:const TextStyle(color:Colors.grey))),
          ]))),
          const SizedBox(height:22),
          const Text('Giới thiệu truyện',style:TextStyle(fontSize:19,fontWeight:FontWeight.bold)),
          const SizedBox(height:9),
          Text(description.isEmpty?'Chưa có mô tả cho truyện này.':description,maxLines:showFullDescription?null:5,overflow:showFullDescription?TextOverflow.visible:TextOverflow.ellipsis,style:const TextStyle(fontSize:15,height:1.65)),
          if(description.length>180)Align(alignment:Alignment.centerLeft,child:TextButton(onPressed:()=>setState(()=>showFullDescription=!showFullDescription),child:Text(showFullDescription?'Thu gọn':'Xem thêm'))),
          const SizedBox(height:16),
          SizedBox(width:double.infinity,child:FilledButton.icon(onPressed:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>ReadingPage(title:s['title'] as String,author:s['author'] as String? ?? '',content:s['content'] as String? ?? ''))),icon:const Icon(Icons.menu_book),label:const Text('ĐỌC TRUYỆN'))),
          const SizedBox(height:10),
          OutlinedButton.icon(onPressed:toggleFavorite,icon:Icon(favorite?Icons.favorite:Icons.favorite_border),label:Text(favorite?'Đã thêm vào yêu thích':'Thêm vào yêu thích')),
          const SizedBox(height:26),
          const Text('Đánh giá của bạn',style:TextStyle(fontSize:19,fontWeight:FontWeight.bold)),
          const SizedBox(height:8),
          Row(children:List.generate(5,(index)=>IconButton(onPressed:()=>rate(index+1),icon:Icon(index<myRating?Icons.star:Icons.star_border,color:Colors.amber,size:34)))),
          Text(myRating==0?'Chọn số sao để đánh giá truyện':'Bạn đã đánh giá $myRating/5 sao',style:const TextStyle(color:Colors.grey)),
          if(related.isNotEmpty) ...[
            const SizedBox(height:28),
            const Text('Truyện cùng thể loại',style:TextStyle(fontSize:19,fontWeight:FontWeight.bold)),
            const SizedBox(height:12),
            SizedBox(height:190,child:ListView.separated(scrollDirection:Axis.horizontal,itemCount:related.length,separatorBuilder:(_,__)=>const SizedBox(width:12),itemBuilder:(ctx,index){
              final item=related[index];
              return SizedBox(width:135,child:InkWell(borderRadius:BorderRadius.circular(12),onTap:()=>Navigator.pushReplacement(context,MaterialPageRoute(builder:(_)=>StoryDetailPage(story:item,user:widget.user))),child:Card(clipBehavior:Clip.antiAlias,child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                Expanded(child:buildCover(item,height:120)),
                Padding(padding:const EdgeInsets.all(8),child:Text(item['title'] as String,maxLines:2,overflow:TextOverflow.ellipsis,style:const TextStyle(fontWeight:FontWeight.bold))),
              ])))) ;
            })),
          ],
        ])),
      ])),
    );
  }
}
