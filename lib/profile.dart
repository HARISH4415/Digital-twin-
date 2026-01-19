import 'dart:io';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _supabase = Supabase.instance.client;
  
  // Controllers
  final _nameController = TextEditingController();
  final _heightController = TextEditingController(); // <--- NEW
  final _weightController = TextEditingController(); // <--- NEW
  
  String? _avatarUrl;
  bool _isLoading = false;
  File? _imageFile;

  @override
  void initState() {
    super.initState();
    _getProfile();
  }

  Future<void> _getProfile() async {
    setState(() => _isLoading = true);
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      final data = await _supabase
          .from('profiles')
          .select()
          .eq('id', user.id)
          .maybeSingle();

      if (data != null) {
        setState(() {
          _nameController.text = data['full_name'] ?? '';
          _avatarUrl = data['avatar_url'];
          // Convert numeric to string for the text fields
          _heightController.text = data['height']?.toString() ?? '';
          _weightController.text = data['weight']?.toString() ?? '';
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error loading profile'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _updateProfile() async {
    setState(() => _isLoading = true);
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      String? imageUrl = _avatarUrl;

      // 1. Upload Image if changed
      if (_imageFile != null) {
        final fileExt = _imageFile!.path.split('.').last;
        final fileName = '${user.id}-${DateTime.now().millisecondsSinceEpoch}.$fileExt';
        
        await _supabase.storage.from('avatars').upload(
          fileName,
          _imageFile!,
          fileOptions: const FileOptions(upsert: true),
        );

        imageUrl = _supabase.storage.from('avatars').getPublicUrl(fileName);
      }

      // 2. Save Data (Name, Height, Weight)
      await _supabase.from('profiles').upsert({
        'id': user.id,
        'full_name': _nameController.text.trim(),
        'avatar_url': imageUrl,
        'height': double.tryParse(_heightController.text.trim()), // Save as number
        'weight': double.tryParse(_weightController.text.trim()), // Save as number
        'updated_at': DateTime.now().toIso8601String(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile updated!'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating profile: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _pickImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    
    if (image != null) {
      setState(() {
        _imageFile = File(image.path);
      });
    }
  }

  Future<void> _signOut() async {
    await _supabase.auth.signOut();
    if (mounted) Navigator.of(context).pop(); 
  }

  @override
  Widget build(BuildContext context) {
    final user = _supabase.auth.currentUser;
    final email = user?.email ?? "Guest";

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text("My Profile"),
        centerTitle: true,
        backgroundColor: Colors.blue.shade700,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 20),
            
            // --- AVATAR ---
            Center(
              child: GestureDetector(
                onTap: _pickImage,
                child: Stack(
                  children: [
                    Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.blue.shade100, width: 4),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.blue.withOpacity(0.1),
                            blurRadius: 10,
                            offset: const Offset(0, 5),
                          )
                        ],
                      ),
                      child: ClipOval(
                        child: _getAvatarImage(email),
                      ),
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade700,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: const Icon(Icons.camera_alt, color: Colors.white, size: 20),
                      ),
                    )
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 24),
            
            // --- NAME ---
            Center(
              child: TextField(
                controller: _nameController,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 22, 
                  fontWeight: FontWeight.bold, 
                  color: Colors.black87
                ),
                decoration: InputDecoration(
                  hintText: "Enter your name",
                  hintStyle: TextStyle(color: Colors.grey.shade400),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
            
            Text(
              email,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
            ),
            
            const SizedBox(height: 32),

            // --- HEIGHT & WEIGHT ROW ---
            Row(
              children: [
                Expanded(
                  child: _buildStatField(
                    "Height", 
                    "cm", 
                    _heightController, 
                    Icons.height
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildStatField(
                    "Weight", 
                    "kg", 
                    _weightController, 
                    Icons.monitor_weight_outlined
                  ),
                ),
              ],
            ),

            const SizedBox(height: 32),

            // --- SAVE BUTTON ---
            SizedBox(
              width: 200,
              height: 45,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _updateProfile,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue.shade700,
                  foregroundColor: Colors.white,
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
                ),
                child: _isLoading 
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text("Save Changes", style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
            
            const SizedBox(height: 32),

            // --- MENU ITEMS ---
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.blue.shade50),
              ),
              child: Column(
                children: [
                  _buildProfileItem(Icons.settings_outlined, "App Settings"),
                  Divider(height: 1, color: Colors.grey.shade100),
                  _buildProfileItem(Icons.notifications_outlined, "Notifications"),
                  Divider(height: 1, color: Colors.grey.shade100),
                  _buildProfileItem(Icons.privacy_tip_outlined, "Privacy Policy"),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // --- SIGN OUT ---
            TextButton.icon(
              onPressed: _signOut,
              icon: const Icon(Icons.logout),
              label: const Text("Sign Out"),
              style: TextButton.styleFrom(
                foregroundColor: Colors.red.shade700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- WIDGET HELPER FOR HEIGHT/WEIGHT ---
  Widget _buildStatField(String label, String unit, TextEditingController controller, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: Colors.blue.shade700),
              const SizedBox(width: 4),
              Text(label, style: TextStyle(color: Colors.blue.shade700, fontSize: 12, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                    border: InputBorder.none,
                    hintText: "0",
                  ),
                ),
              ),
              Text(unit, style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.w500)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _getAvatarImage(String email) {
    if (_imageFile != null) {
      return Image.file(_imageFile!, fit: BoxFit.cover);
    } else if (_avatarUrl != null && _avatarUrl!.isNotEmpty) {
      return Image.network(
        _avatarUrl!,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => _buildInitials(email),
      );
    } else {
      return _buildInitials(email);
    }
  }

  Widget _buildInitials(String email) {
    final initial = email.isNotEmpty ? email[0].toUpperCase() : "?";
    return Center(
      child: Text(
        initial,
        style: TextStyle(
          fontSize: 40,
          fontWeight: FontWeight.bold,
          color: Colors.blue.shade700,
        ),
      ),
    );
  }

  Widget _buildProfileItem(IconData icon, String title) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.blue.shade50,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.blue.shade700, size: 20),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
      trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
      onTap: () {},
    );
  }
}