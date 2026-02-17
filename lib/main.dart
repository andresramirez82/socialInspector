import 'dart:convert';
import 'dart:io'; 
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; 
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart'; 
import 'package:url_launcher/url_launcher.dart';
import 'about.dart';
import 'constants.dart';

void main() => runApp(const SherlockApp());

class SherlockApp extends StatelessWidget {
  const SherlockApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: appName,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6366F1),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          elevation: 0,
          backgroundColor: Color(0xFF6366F1),
          foregroundColor: Colors.white,
          centerTitle: false,
          scrolledUnderElevation: 0,
        ),
        textTheme: const TextTheme(
          headlineLarge: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.bold,
            color: Color(0xFF1F2937),
          ),
          headlineSmall: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Color(0xFF1F2937),
          ),
          bodyMedium: TextStyle(
            fontSize: 14,
            color: Color(0xFF6B7280),
            height: 1.6,
          ),
        ),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6366F1),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const SherlockHome(),
    );
  }
}

class SherlockHome extends StatefulWidget {
  const SherlockHome({super.key});

  @override
  State<SherlockHome> createState() => _SherlockHomeState();
}

class _SherlockHomeState extends State<SherlockHome> {
  final TextEditingController _controller = TextEditingController();
  Map<String, dynamic> _sitesData = {};
  final List<Map<String, String>> _results = [];
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    _loadJsonData();
  }

  // Carga el archivo data.json desde los assets
  Future<void> _loadJsonData() async {
    try {
      final String response = await rootBundle.loadString('assets/data.json');
      setState(() {
        _sitesData = json.decode(response);
      });
    } catch (e) {
      debugPrint("Error cargando JSON: $e");
    }
  }

  // Función para exportar resultados a TXT
  Future<void> _exportResults() async {
    if (_results.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No hay resultados para exportar")),
      );
      return;
    }

    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/resultados_social_inspector.txt');

      String content = "SOCIAL INSPECTOR - RESULTADOS\n";
      content += "Usuario buscado: ${_controller.text}\n";
      content += "Fecha: ${DateTime.now()}\n";
      content += "==================================\n\n";
      
      for (var result in _results) {
        content += "Sitio: ${result['name']}\nURL: ${result['url']}\n\n";
      }

      await file.writeAsString(content);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Guardado en Documentos: ${file.path}")),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Error al exportar archivo")),
      );
    }
  }

  Future<void> _searchUser() async {
    final username = _controller.text.trim();
    if (username.isEmpty) return;

    setState(() {
      _results.clear();
      _isSearching = true;
    });

    // Lista de tareas para ejecutar en paralelo
    List<Future> searchTasks = [];

    for (var entry in _sitesData.entries) {
      if (entry.key.startsWith('\$')) continue; 

      final siteName = entry.key;
      final config = entry.value;
      final String url = config['url'].replaceAll('{}', username);

      searchTasks.add(_checkSite(siteName, url, config));
    }

    // Esperar a que todas las peticiones terminen
    await Future.wait(searchTasks);

    setState(() {
      _isSearching = false;
    });
  }

  Future<void> _checkSite(String name, String url, dynamic config) async {
    try {
      final username = _controller.text.trim();
      bool exists = false;

      // Validar formato del username contra regexCheck si existe
      if (config['regexCheck'] != null) {
        final regex = RegExp(config['regexCheck']);
        if (!regex.hasMatch(username)) {
          return; // Usuario no cumple el patrón, no existe en esta red
        }
      }

      // Prioridad 1: Usar urlProbe si está disponible
      if (config['urlProbe'] != null) {
        final probeUrl = config['urlProbe'].replaceAll('{}', username);
        
        if (config['errorType'] == 'status_code') {
          final response = await http.get(Uri.parse(probeUrl)).timeout(const Duration(seconds: 10));
          exists = (response.statusCode == 200);
        } else if (config['errorType'] == 'message') {
          final response = await http.get(Uri.parse(probeUrl)).timeout(const Duration(seconds: 10));
          final errorMsg = config['errorMsg'];
          
          // Si NO contiene el mensaje de error = usuario existe
          bool hasErrorMsg = false;
          if (errorMsg is String) {
            hasErrorMsg = response.body.contains(errorMsg);
          } else if (errorMsg is List) {
            hasErrorMsg = errorMsg.any((m) => response.body.contains(m.toString()));
          }
          exists = !hasErrorMsg;
        }
      } else {
        // Prioridad 2: Usar URL principal si no hay urlProbe
        if (config['errorType'] == 'status_code') {
          final response = await http.head(Uri.parse(url)).timeout(const Duration(seconds: 10));
          exists = (response.statusCode == 200);
        } else if (config['errorType'] == 'message') {
          final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
          final errorMsg = config['errorMsg'];
          
          // Si NO contiene el mensaje de error = usuario existe
          bool hasErrorMsg = false;
          if (errorMsg is String) {
            hasErrorMsg = response.body.contains(errorMsg);
          } else if (errorMsg is List) {
            hasErrorMsg = errorMsg.any((m) => response.body.contains(m.toString()));
          }
          exists = !hasErrorMsg;
        }
      }

      if (exists) {
        setState(() {
          _results.add({'name': name, 'url': url});
        });
      }
    } catch (e) {
      debugPrint("Error verificando $name: $e");
      // Ignorar errores de conexión o timeouts
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;
    final isTablet = MediaQuery.of(context).size.width >= 600 && MediaQuery.of(context).size.width < 1200;
    
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.search, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  appName,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
                Text(
                  'v$appVersion',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.white.withOpacity(0.8),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline, color: Colors.white),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const AboutPage(),
                ),
              );
            },
            tooltip: 'Acerca de',
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white,
              Colors.blue.shade100.withOpacity(0.4),
              Colors.indigo.shade100.withOpacity(0.3),
            ],
            stops: const [0.0, 0.5, 1.0],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                isMobile ? 16 : 32,
                24,
                isMobile ? 16 : 32,
                24,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Encabezado informativo
                  Padding(
                    padding: const EdgeInsets.only(bottom: 32),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Busca perfiles',
                          style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                            color: const Color(0xFF111827),
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          height: 4,
                          width: 60,
                          decoration: BoxDecoration(
                            color: const Color(0xFF6366F1),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Descubre si un usuario existe en múltiples redes sociales simultaneamente',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontSize: 15,
                            color: const Color(0xFF374151),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Campo de búsqueda mejorado
                  Container(
                    decoration: BoxDecoration(
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.08),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: TextField(
                      controller: _controller,
                      onSubmitted: (_) => _searchUser(),
                      enabled: !_isSearching,
                      decoration: InputDecoration(
                        labelText: 'Nombre de usuario',
                        labelStyle: const TextStyle(
                          color: Color(0xFF6366F1),
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                        hintText: 'Ej: freddier, john_doe',
                        hintStyle: TextStyle(
                          color: Colors.grey[500],
                          fontSize: 14,
                          fontWeight: FontWeight.w400,
                        ),
                        prefixIcon: const Padding(
                          padding: EdgeInsets.only(left: 16, right: 12),
                          child: Icon(Icons.person, size: 24, color: Color(0xFF6366F1)),
                        ),
                        suffixIcon: _isSearching
                          ? Container(
                              margin: const EdgeInsets.all(8),
                              child: const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            )
                          : Padding(
                              padding: const EdgeInsets.all(4),
                              child: Container(
                                margin: const EdgeInsets.only(right: 4),
                                child: Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    onTap: _isSearching ? null : _searchUser,
                                    borderRadius: BorderRadius.circular(12),
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF6366F1),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: const Icon(Icons.search, color: Colors.white),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: const BorderSide(color: Color(0xFFE5E7EB), width: 2),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: const BorderSide(color: Color(0xFFE5E7EB), width: 2),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: const BorderSide(
                            color: Color(0xFF6366F1),
                            width: 2.5,
                          ),
                        ),
                        filled: true,
                        fillColor: const Color(0xFFFAFAFA),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: isMobile ? 16 : 20,
                          vertical: isMobile ? 14 : 18,
                        ),
                      ),
                      style: const TextStyle(
                        fontSize: 16,
                        color: Color(0xFF1F2937),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),

                  const SizedBox(height: 28),

                  // Indicador de carga mejorado
                  if (_isSearching) ...[
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.indigo.shade50,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: const Color(0xFF6366F1).withOpacity(0.2),
                        ),
                      ),
                      child: Column(
                        children: [
                          const SizedBox(
                            width: 50,
                            height: 50,
                            child: CircularProgressIndicator(
                              strokeWidth: 3,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Color(0xFF6366F1),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Buscando en ${_sitesData.length} plataformas...',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF4F46E5),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Esto puede tomar unos segundos',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],

                  // Zona de resultados
                  if (!_isSearching) ...[
                    if (_results.isEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 40),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.search,
                              size: 64,
                              color: Colors.grey[300],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Ingresa un nombre de usuario',
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                color: Colors.grey[600],
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Buscaremos en todas las redes sociales disponibles',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Colors.grey[500],
                              ),
                            ),
                          ],
                        ),
                      )
                    else ...[
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Resultados encontrados',
                                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: const Color(0xFF111827),
                                  ),
                                ),
                                Text(
                                  '${_results.length} perfil${_results.length != 1 ? 'es' : ''} activo${_results.length != 1 ? 's' : ''}',
                                  style: TextStyle(
                                    color: Colors.grey[700],
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                            if (_results.isNotEmpty)
                              Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: _exportResults,
                                  borderRadius: BorderRadius.circular(12),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF6366F1),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.download, color: Colors.white, size: 16),
                                        SizedBox(width: 8),
                                        Text(
                                          'Exportar',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      // Grid o Lista de resultados
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: isMobile ? 1 : (isTablet ? 2 : 3),
                          mainAxisSpacing: 16,
                          crossAxisSpacing: 16,
                          childAspectRatio: isMobile ? 1 : 1.1,
                        ),
                        itemCount: _results.length,
                        itemBuilder: (context, index) {
                          final siteName = _results[index]['name']!;
                          final siteUrl = _results[index]['url']!;
                          final String domain = Uri.parse(siteUrl).host;
                          final String iconUrl = "https://www.google.com/s2/favicons?domain=$domain&sz=128";

                          return AnimatedOpacity(
                            opacity: 1.0,
                            duration: Duration(milliseconds: 300 + (index * 50)),
                            child: _buildResultCard(
                              siteName,
                              siteUrl,
                              iconUrl,
                              context,
                            ),
                          );
                        },
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }}
  Widget _buildResultCard(
    String siteName,
    String siteUrl,
    String iconUrl,
    BuildContext context,
  ) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () async {
          final Uri uri = Uri.parse(siteUrl);
          if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("No se pudo abrir la URL")),
            );
          }
        },
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: const Color(0xFFE5E7EB),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Stack(
            children: [
              // Fondo decorativo
              Positioned(
                top: -20,
                right: -20,
                child: Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    color: const Color(0xFF6366F1).withOpacity(0.05),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              // Contenido
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Icono
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: const Color(0xFF6366F1).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Image.network(
                            iconUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) => const Icon(
                              Icons.public,
                              color: Color(0xFF6366F1),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        // Nombre del sitio
                        Text(
                          siteName,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1F2937),
                          ),
                        ),
                      ],
                    ),
                    // Link y botón
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          siteUrl,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[600],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.green.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                'Encontrado',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.green,
                                ),
                              ),
                            ),
                            const Icon(
                              Icons.open_in_new,
                              size: 16,
                              color: Color(0xFF6366F1),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }