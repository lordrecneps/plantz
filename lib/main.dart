import 'dart:io';

import "package:collection/collection.dart";
import 'package:flutter/material.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';

void main() {
  runApp(Plantz());
}

void createTables(Database db) {
  db.execute(
    "CREATE TABLE IF NOT EXISTS plants(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, frequency INTEGER)",
  );
  db.execute(
    "CREATE TABLE IF NOT EXISTS actions(id INTEGER PRIMARY KEY AUTOINCREMENT, plant_id INTEGER, action TEXT, timestamp INTEGER, FOREIGN KEY(plant_id) REFERENCES plants(id))",
  );
  db.execute(
    "CREATE TABLE IF NOT EXISTS photos(id INTEGER PRIMARY KEY AUTOINCREMENT, plant_id INTEGER, path TEXT, timestamp INTEGER, FOREIGN KEY(plant_id) REFERENCES plants(id))",
  );
}

Future<Database> getDatabase() async {
  return openDatabase(
    join(await getDatabasesPath(), 'plantz.db'),
    onUpgrade: (db, oldversion, newVersion) {
      createTables(db);
    },
    onDowngrade: (db, oldversion, newVersion) {
      createTables(db);
    },
    version: 1,
  );
}

int getCurrentTimestamp() {
  return (DateTime.now().millisecondsSinceEpoch / 1000).round();
}

class Plantz extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Plantz',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      initialRoute: '/',
      routes: {
        '/': (context) => MainPage(title: 'Plantz'),
      },
      onGenerateRoute: (settings) {
        if (settings.name == '/detail') {
          final plant = settings.arguments;
          return MaterialPageRoute(
            builder: (context) {
              return PlantDetailPage(
                plant: plant,
              );
            },
          );
        }
      },
    );
  }
}

class PlantDetailPage extends StatefulWidget {
  PlantDetailPage({Key key, this.plant}) : super(key: key);

  Plant plant;
  @override
  _PlantDetailPageState createState() => _PlantDetailPageState();
}

class _PlantDetailPageState extends State<PlantDetailPage> {
  TextEditingController controller;
  Database db;
  Plant plant;
  List<int> waterings = [];
  TextEditingController frequencyController;
  final picker = ImagePicker();

  Future getImage() async {
    final pickedFile = await picker.getImage(source: ImageSource.camera);
    int ts = getCurrentTimestamp();
    await db.insert(
      'photos',
      {'plant_id': plant.id, 'path': pickedFile.path, 'timestamp': ts},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    setState(() {
      plant.imagePath = pickedFile.path;
    });
  }

  Future<List<int>> loadPlant() async {
    db = await getDatabase();
    var results = await db.query('actions',
        where: "plant_id = ? and action = 'water'", whereArgs: [plant.id]);
    var ret =
        List.generate(results.length, (i) => results[i]['timestamp'] as int);
    ret.sort((t1, t2) => t2 - t1);
    return ret;
  }

  @override
  void initState() {
    super.initState();
    plant = widget.plant;
    controller = TextEditingController(text: plant.name);
    frequencyController =
        TextEditingController(text: plant.frequency.toString());
    loadPlant().then((result) {
      setState(() {
        waterings = result;
      });
    });
  }

  Future<void> water() async {
    int ts = getCurrentTimestamp();
    await db.insert(
      'actions',
      {'plant_id': plant.id, 'action': 'water', 'timestamp': ts},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    setState(() {
      waterings.add(ts);
    });
  }

  Future<void> updateFrequency(int days) async {
    days = days < 0 ? 0 : days;
    await db.update('plants', {'frequency': days},
        where: "id = ?", whereArgs: [plant.id]);
    plant.frequency = days;
  }

  Future<void> updateName(String name) async {
    await db.update('plants', {'name': name},
        where: "id = ?", whereArgs: [plant.id]);
    plant.name = name;
  }

  @override
  Widget build(BuildContext context) {
    List<Widget> widgets = [
      TextField(
        decoration: new InputDecoration(labelText: "Name"),
        controller: controller,
        keyboardType: TextInputType.text,
        onEditingComplete: () {
          updateName(controller.text);
        },
      ),
      TextField(
        decoration: new InputDecoration(labelText: "Frequency"),
        controller: frequencyController,
        keyboardType: TextInputType.number,
        onEditingComplete: () {
          updateFrequency(int.tryParse(frequencyController.text) ?? 0);
        },
      ),
      FlatButton(
        child: Text('Add Image'),
        onPressed: () {
          getImage();
        },
      )
    ];
    if (plant.imagePath != null) {
      widgets.add(Image.file(File(plant.imagePath)));
    }
    widgets.addAll(waterings
        .map((timestamp) => Card(
              child: ListTile(
                title: Text(DateFormat('d MMM y – kk:mm:ss').format(
                    new DateTime.fromMillisecondsSinceEpoch(timestamp * 1000))),
              ),
            ))
        .toList());
    return Scaffold(
      appBar: AppBar(
        title: Text(plant.name),
      ),
      body: Center(child: ListView(children: widgets)),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          water();
        },
        tooltip: 'Water',
        child: Icon(Icons.bubble_chart),
      ),
    );
  }
}

class MainPage extends StatefulWidget {
  MainPage({Key key, this.title}) : super(key: key);

  final String title;

  @override
  _MainPageState createState() => _MainPageState();
}

class Plant {
  String name;
  final int id;
  int frequency;
  int ts;
  String imagePath;

  Plant(this.name, this.id, this.frequency, this.ts, this.imagePath);
}

class _MainPageState extends State<MainPage> {
  TextEditingController frequencyController;
  TextEditingController addController;
  List<Plant> plants = [];
  Database db;

  Future<void> addPlant(String plant, int frequency) async {
    if (plant.isEmpty) {
      return;
    }
    var id = await db.insert(
      'plants',
      {'name': plant, 'frequency': frequency},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    setState(() {
      plants.add(Plant(plant, id, frequency, 0, null));
      sortPlantList(plants);
    });
  }

  int plantSort(Plant p1, Plant p2, int now) {
    var p1time = p1.ts + p1.frequency * 86400;
    var p2time = p2.ts + p2.frequency * 86400;
    if (p1.frequency == 0) {
      p1time = now + 1;
    }
    if (p2.frequency == 0) {
      p2time = now + 1;
    }
    if ((p1time <= now && p2time <= now) || (p1time > now && p2time > now)) {
      return p1.name.compareTo(p2.name);
    }
    if (p1time <= now) {
      return -1;
    }
    return 1;
  }

  void sortPlantList(List<Plant> list) {
    var now = getCurrentTimestamp();
    list.sort((Plant a, Plant b) => plantSort(a, b, now));
  }

  Future<List<Plant>> loadPlants() async {
    db = await getDatabase();
    final List<Map<String, dynamic>> maps = await db.rawQuery(
        "SELECT plants.id as id, name, frequency, action, max(timestamp) as ts from plants left outer join actions on plants.id = plant_id group by plants.id, name, frequency, action");
    final List<Map<String, dynamic>> photos =
        await db.rawQuery("SELECT * from photos");
    var groupedPhotos = groupBy(photos, (photo) => photo['plant_id']);
    var ret = List.generate(
        maps.length,
        (i) => Plant(
            maps[i]['name'],
            maps[i]['id'],
            maps[i]['frequency'] ?? 0,
            maps[i]['ts'] ?? 0,
            groupedPhotos.containsKey(maps[i]['id']) ? groupedPhotos[maps[i]['id']].reduce((value, element) =>
                value['timestamp'] > element['timestamp']
                    ? value
                    : element)['path'] : null));
    sortPlantList(ret);
    return ret;
  }

  @override
  void initState() {
    super.initState();

    frequencyController = TextEditingController(text: "7");
    addController = TextEditingController();
    loadPlants().then((result) {
      setState(() {
        plants = result;
      });
    });
  }

  bool needsWatering(Plant p) {
    if (p.frequency == 0) {
      return false;
    }
    var now = getCurrentTimestamp();
    return (now - p.ts - p.frequency * 86400) > 0;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
      ),
      body: Center(
        child: RefreshIndicator(
          child: ListView(
              children: plants
                  .map((p) => Card(
                        child: Material(
                            color: needsWatering(p) ? Colors.red : null,
                            child: ListTile(
                                contentPadding: p.imagePath != null ? EdgeInsets.only(left: 0.0, right: 16.0) : null,
                                leading: p.imagePath != null ? Image.file(File(p.imagePath), fit: BoxFit.fitHeight) : FlutterLogo(),
                                title: Text(p.name),
                                trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      FlatButton(
                                          child: Icon(Icons.bubble_chart),
                                          onPressed: () {
                                            var ts = getCurrentTimestamp();
                                            db
                                                .insert(
                                              'actions',
                                              {
                                                'plant_id': p.id,
                                                'action': 'water',
                                                'timestamp': ts
                                              },
                                              conflictAlgorithm:
                                                  ConflictAlgorithm.replace,
                                            )
                                                .then((e) {
                                              setState(() {
                                                p.ts = ts;
                                                sortPlantList(plants);
                                              });
                                            });
                                          }),
                                      PopupMenuButton<String>(
                                        onSelected: (String value) {
                                          setState(() {});
                                        },
                                        child: Icon(Icons.more_vert),
                                        itemBuilder: (BuildContext context) =>
                                            <PopupMenuEntry<String>>[
                                          const PopupMenuItem<String>(
                                            value: 'water',
                                            child: Text('Water'),
                                          ),
                                          const PopupMenuItem<String>(
                                            value: 'fertilize',
                                            child: Text('Fertilize'),
                                          ),
                                          const PopupMenuItem<String>(
                                            value: 'snooze',
                                            child: Text('Snooze 1 day'),
                                          ),
                                        ],
                                      )
                                    ]),
                                onTap: () {
                                  Navigator.pushNamed(context, '/detail',
                                          arguments: p)
                                      .then((e) {
                                    loadPlants().then((result) {
                                      setState(() {
                                        plants = result;
                                      });
                                    });
                                  });
                                })),
                      ))
                  .toList()),
          onRefresh: () {
            return loadPlants().then((result) {
              setState(() {
                plants = result;
              });
            });
          },
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          showDialog(
              child: new Dialog(
                child: new Column(
                  children: <Widget>[
                    new TextField(
                      decoration: new InputDecoration(labelText: "Name"),
                      controller: addController,
                    ),
                    new TextField(
                      decoration: new InputDecoration(labelText: "Frequency"),
                      keyboardType: TextInputType.number,
                      controller: frequencyController,
                    ),
                    new FlatButton(
                      child: new Text("Add"),
                      onPressed: () {
                        addPlant(addController.text,
                            int.tryParse(frequencyController.text) ?? 7);
                        Navigator.pop(context);
                      },
                    ),
                    new FlatButton(
                      child: new Text("Cancel"),
                      onPressed: () {
                        Navigator.pop(context);
                      },
                    )
                  ],
                ),
              ),
              context: context);
        },
        tooltip: 'Add plant',
        child: Icon(Icons.add),
      ),
    );
  }
}
