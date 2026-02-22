// lib/screens/admin_tools_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:provider/provider.dart' show WatchContext, ReadContext;
import '../../UI/app_bar.dart';
import '../../UI/app_buttons.dart';
import '../../UI/app_colors.dart';
import '../../auth/login/auth_service.dart';
import '../../backend_data/service/ads/premium_provider.dart';
import '../../backend_data/service/ads/premium_subscription_screen.dart';
import '../../backend_data/service/ads/subscribe_button.dart';
import '../../l10n/app_localizations.dart';

class AdminToolsScreen extends StatefulWidget {
  const AdminToolsScreen({super.key});

  @override
  State<AdminToolsScreen> createState() => AdminToolsScreenState();
}

class AdminToolsScreenState extends State<AdminToolsScreen> {
  final emailController = TextEditingController();

  bool _isChurchAdminLoading = false;
  bool _isGroupAdminLoading = false;
  bool _isRemovingChurchAdmin = false;
  bool _isRemovingGroupAdmin = false;

  String? _selectedAdminToRemove;
  String? _selectedGroupToRemove;

  String? _message;
  bool _isSuccess = false;

  // Hardcoded allowed groups (you can change/add later)
  final List<String?> _allowedGroups = [
    "Sunday School",
    null,
    //"Teens",
    //"Youth",
    //"Children",
    //"Adults",
    //"Women",
    //"Men",
    //"Couples",
    //"Singles",
  ];

  String? _selectedGroup;

  @override
  void dispose() {
    emailController.dispose();
    super.dispose();
  }

  Future<void> _makeAdmin({required bool isMakingGroupAdmin}) async {
    final email = emailController.text.trim().toLowerCase();
    final auth = context.read<AuthService>();

    if (email.isEmpty) {
      setState(() {
        _message = "Email is required";
        _isSuccess = false;
      });
      return;
    }

    // Validation: require group only when making group admin
    if (isMakingGroupAdmin && (_selectedGroup == null || _selectedGroup!.isEmpty)) {
      setState(() {
        _message = "Please select a group";
        _isSuccess = false;
      });
      return;
    }

    setState(() {
      if (isMakingGroupAdmin) {
        _isGroupAdminLoading = true;
      } else {
        _isChurchAdminLoading = true;
      }
      _message = null;
    });

    try {
      final callable = FirebaseFunctions.instance
          .httpsCallable('makeChurchOrGroupAdmin');

      await callable.call({
        'userEmail': email,
        'churchId': auth.churchId,
        'groupId': isMakingGroupAdmin ? _selectedGroup : null,
      });

      setState(() {
        _message = isMakingGroupAdmin
            ? "Success! $email is now a group admin for \"$_selectedGroup\""
            : "Success! $email is now a church admin";
        _isSuccess = true;
      });

      // Clear inputs
      emailController.clear();
      _selectedGroup = null;

    } on FirebaseFunctionsException catch (e) {
      setState(() {
        _message = "Error: ${e.message ?? 'Unknown error'}";
        _isSuccess = false;
      });
    } catch (e) {
      setState(() {
        _message = "Failed: $e";
        _isSuccess = false;
      });
    } finally {
      setState(() {
        _isChurchAdminLoading = false;
        _isGroupAdminLoading = false;
      });
    }
  }

  Future<void> _removeAdmin({required bool isGroupSpecific}) async {
    final auth = context.read<AuthService>();
    if (kDebugMode) {
      debugPrint("Selected UID: $_selectedAdminToRemove");
      debugPrint("Church ID: ${auth.churchId}");
    }

    if (_selectedAdminToRemove == null) {
      _message = "Please select an admin first";
      return;
    }

    setState(() {
      if (isGroupSpecific) {
        _isRemovingGroupAdmin = true;
      } else {
        _isRemovingChurchAdmin = true;
      }
      _message = null;
    });

    try {
      await FirebaseFunctions.instance
          .httpsCallable('removeChurchOrGroupAdmin')
          .call({
        'userUid': _selectedAdminToRemove,
        'churchId': auth.churchId!,
        'groupId': isGroupSpecific ? _selectedGroupToRemove : null,
      });

      _message = isGroupSpecific
        ? "Removed from group \"$_selectedGroupToRemove\""
        : "All church admin rights removed";

      setState(() {
        _isSuccess = true;
        _selectedAdminToRemove = null;
        _selectedGroupToRemove = null;
      });

    } on FirebaseFunctionsException catch (e) {
      setState(() {
        _message = "Error: ${e.message ?? 'Failed'}";
        _isSuccess = false;
      });
    } finally {
      setState(() {
        _isRemovingChurchAdmin = false;
        _isRemovingGroupAdmin = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // Extra safety: only global admins should see this
    if (!auth.isGlobalAdmin && !auth.isChurchAdmin) {
      return Scaffold(
        appBar: AppAppBar(
          title: AppLocalizations.of(context)?.accessRestricted ?? "Access Restricted",
          showBack: true,
        ),
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(24.sp),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.lock_outline,
                  size: 70.sp,
                ),
                SizedBox(height: 10.sp),
                Text(
                  "Access Denied",
                  style: TextStyle(
                    fontSize: 20.sp, 
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 10.sp),
                Text(
                  "This page is only available to church or global administrators.",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 10.sp, 
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppAppBar(
        title: "Global Admin Tools",
        showBack: true,
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(15.sp),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Promote User to Admin",
              style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8.sp),
            Text(
              "You are logged in as church admin (${auth.currentUser?.email})",
              style: TextStyle(
                fontSize: 15.sp,
              ),
            ),
            SizedBox(height: 20.sp),

            // Email Field
            TextField(
              controller: emailController,
              keyboardType: TextInputType.emailAddress,
              style: TextStyle(
                fontSize: 15.sp,
              ),
              decoration: InputDecoration(
                labelText: "User Email",
                hintText: "e.g. pastor@example.com",

                labelStyle: TextStyle(
                  fontSize: 14.sp,
                  color: colorScheme.onSurface,
                ),
                hintStyle: TextStyle(
                  fontSize: 13.sp,
                  color: colorScheme.onSurface,
                ),

                border: OutlineInputBorder(),
                isDense: true, 
                contentPadding: EdgeInsets.symmetric(horizontal: 12.sp, vertical: 12.sp),
              ),
              
            ),
            SizedBox(height: 10.sp),

            // Group ID Dropdown (only shown when making group admin)
            DropdownButtonFormField<String?>(
              value: _selectedGroup,
              hint: Text("Select a group (optional for church admin)",
              style: TextStyle(
                fontSize: 15.sp,
                color: colorScheme.onSurface,
                ),
              ),
              decoration: InputDecoration(
                labelText: "Group",
                hintText: "Leave empty for church admin",

                labelStyle: TextStyle(
                  fontSize: 14.sp,
                  color: colorScheme.onSurface,
                ),
                hintStyle: TextStyle(
                  fontSize: 13.sp,
                  color: colorScheme.onSurface,
                ),

                border: OutlineInputBorder(),
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 12.sp, vertical: 12.sp),
              ),
              items: _allowedGroups.map((String? group) {
                return DropdownMenuItem<String?>(
                  value: group,
                  child: Text(
                    group ?? "(No group - Church Admin only)",
                    style: TextStyle(
                      fontSize: 13.sp,
                      color: colorScheme.onSurface,
                    ),
                  ),
                );
              }).toList(),
              onChanged: (String? newValue) {
                setState(() {
                  _selectedGroup = newValue;
                });
              },
            ),
            SizedBox(height: 20.sp),

            // Buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: LoginButtons(
                    context: context,
                    topColor: AppColors.success,
                    onPressed: _isChurchAdminLoading ? null : () => _makeAdmin(isMakingGroupAdmin: false),
                    child: _isChurchAdminLoading
                        ? SizedBox(
                            height: 20.sp,
                            width: 20.sp,
                            child: CircularProgressIndicator(
                              color: Colors.white, 
                              strokeWidth: 2.sp,
                            ),
                          )
                        : Text(
                            "Make Church Admin",
                            style: TextStyle(
                              color: Colors.white, 
                              fontWeight: FontWeight.bold,
                              fontSize: 15.sp,
                            ),
                          ),
                    text: '',
                  ),
                ),
                SizedBox(width: 16.sp),
                Expanded(
                  child: LoginButtons(
                    context: context,
                    topColor: AppColors.success,
                    onPressed: _isGroupAdminLoading || _selectedGroup == null || _selectedGroup!.isEmpty? null : () => _makeAdmin(isMakingGroupAdmin: true),
                    child: _isGroupAdminLoading
                        ? SizedBox(
                            height: 20.sp,
                            width: 20.sp,
                            child: CircularProgressIndicator(
                              color: Colors.white, 
                              strokeWidth: 2.sp,
                            ),
                          )
                        : Text(
                            "Make Group Admin",
                            style: TextStyle(
                              color: Colors.white, 
                              fontWeight: FontWeight.bold,
                              fontSize: 15.sp,
                            ),
                          ),
                    text: '',
                  ),
                ),
              ],
            ),

            SizedBox(height: 15.sp),

            // Feedback Message
            if (_message != null)
              Card(
                color: _isSuccess ? Colors.green.shade50 : Colors.red.shade50,
                child: Padding(
                  padding: EdgeInsets.all(16.sp),
                  child: Row(
                    children: [
                      Icon(
                        _isSuccess ? Icons.check_circle : Icons.error,
                        color: _isSuccess ? Colors.green.shade700 : Colors.red.shade700,
                      ),
                      SizedBox(width: 12.sp),
                      Expanded(
                        child: Text(
                          _message!,
                          style: TextStyle(
                            color: _isSuccess ? Colors.green.shade800 : Colors.red.shade800,
                            fontWeight: FontWeight.w600,
                            fontSize: 12.sp,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            Divider(
              thickness: 0.8,
              height: 20.sp,
              color: Colors.grey.shade400.withOpacity(0.6),
            ),
            // Fetch and show list of current admins
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('churches')
                  .doc(auth.churchId!)
                  .collection('admins')
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return Text(
                    "No admins in this church yet",
                    style: TextStyle(
                      fontSize: 14.sp, 
                      color: colorScheme.onSurface,
                    ),
                  );
                }

                final admins = snapshot.data!.docs;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Remove Admin Rights",
                      style: TextStyle(
                        fontSize: 18.sp, 
                        fontWeight: FontWeight.bold,
                        //color: colorScheme.onSurface,
                      ),
                    ),
                    SizedBox(height: 12.sp),

                    // Admin dropdown
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      value: _selectedAdminToRemove,
                      style: TextStyle(
                        fontSize: 16.sp,
                        color: colorScheme.onSurface,
                      ),
                      hint: Text(
                        "Select admin to remove",
                        style: TextStyle(
                          fontSize: 13.sp,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      decoration: InputDecoration(
                        labelText: "Admin",
                        labelStyle: TextStyle(
                          fontSize: 14.sp,
                          color: colorScheme.onSurface,
                        ),
                        border: OutlineInputBorder(),
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(horizontal: 12.sp, vertical: 12.sp),
                      ),
                      items: admins.map((doc) {
                        final data = doc.data();
                        final email = data['email'] ?? 'Unknown';
                        final displayName = data['displayName'] ?? email;
                        return DropdownMenuItem<String>(
                          value: doc.id,
                          child: Text(
                            "$displayName ($email)",
                            style: TextStyle(
                              fontSize: 13.sp,
                              color: colorScheme.onSurface,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }).toList(),
                      onChanged: (String? uid) {
                        setState(() {
                          _selectedAdminToRemove = uid;
                          _selectedGroupToRemove = null;
                        });
                      },
                    ),

                    SizedBox(height: 10.sp),

                    // Group dropdown (only for specific group remove)
                    if (_selectedAdminToRemove != null)
                      StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                        stream: FirebaseFirestore.instance
                            .collection('churches')
                            .doc(auth.churchId!)
                            .collection('admins')
                            .doc(_selectedAdminToRemove)
                            .snapshots(),
                        builder: (context, snapshot) {
                          if (!snapshot.hasData) return const CircularProgressIndicator();
                          final data = snapshot.data!.data()!;
                          final List<String> groups = List<String>.from(data['groups'] ?? []);

                          if (groups.isEmpty) {
                            return Text(
                              "This admin has no group priviledges",
                              style: TextStyle(
                                color: colorScheme.onSurface, 
                                fontSize: 14.sp,
                              ),
                            );
                          }

                          return DropdownButtonFormField<String>(
                            value: _selectedGroupToRemove,
                            hint: Text(
                              "Select group to remove",
                              style: TextStyle(
                                fontSize: 13.sp,
                                color: colorScheme.onSurface,
                              ),
                            ),
                            decoration: InputDecoration(
                              labelText: "Group",
                              labelStyle: TextStyle(
                                fontSize: 14.sp,
                                color: colorScheme.onSurface,
                              ),
                              border: OutlineInputBorder(),
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(horizontal: 12.sp, vertical: 12.sp),
                            ),
                            items: groups.map((group) {
                              return DropdownMenuItem<String>(
                                value: group,
                                child: Text(
                                  group,
                                  style: TextStyle(
                                    fontSize: 13.sp,
                                    color: colorScheme.onSurface,
                                  ),
                                ),
                              );
                            }).toList(),
                            onChanged: (String? group) => setState(() => _selectedGroupToRemove = group),
                          );
                        },
                      ),

                    SizedBox(height: 10.sp),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: LoginButtons(
                            context: context,
                            topColor: AppColors.primaryContainer,
                            onPressed: _isRemovingChurchAdmin || _selectedAdminToRemove == null
                                ? null
                                : () => _removeAdmin(isGroupSpecific: false),
                            child: _isRemovingChurchAdmin
                                ? SizedBox(height: 20.sp, width: 20.sp, child: CircularProgressIndicator(
                                  color: Colors.white, 
                                  strokeWidth: 2.sp,
                                ))
                                : Text("Remove Church Admin", 
                                style: TextStyle(
                                  color: Colors.white, 
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15.sp,
                                )),
                            text: '',
                          ),
                        ),
                        SizedBox(width: 16.sp),
                        Expanded(
                          child: LoginButtons(
                            context: context,
                            topColor: AppColors.primaryContainer,
                            onPressed: _isRemovingGroupAdmin || _selectedAdminToRemove == null
                                ? null
                                : () => _removeAdmin(isGroupSpecific: true),
                            child: _isRemovingGroupAdmin
                                ? SizedBox(height: 20.sp, width: 20.sp, child: CircularProgressIndicator(
                                  color: Colors.white, 
                                  strokeWidth: 2.sp,
                                ))
                                : Text("Remove from Group", 
                                style: TextStyle(
                                  color: Colors.white, 
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15.sp,
                                )),
                            text: '',
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),

            SizedBox(height: 10.sp),

            // Helpful Tips
            Center(
              child: Card(
                child: Padding(
                  padding: EdgeInsets.all(10.sp),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("Tips:", 
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 10.sp,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      SizedBox(height: 8.sp),
                      Text("• Making someone Church Admin gives them full control over parish priviledges", 
                        style: TextStyle(
                          color: colorScheme.onSurface,
                          fontSize: 8.sp,
                        ),
                      ),
                      Text("• Group Admin only has group priviledges",
                        style: TextStyle(
                          color: colorScheme.onSurface,
                          fontSize: 8.sp,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            SizedBox(height: 10.sp),

            /*/ === NEW: Church Premium Subscription Button ===
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Consumer(
                    builder: (context, ref, child) {
                      final asyncPremium = ref.watch(isPremiumProvider);
                  
                      return asyncPremium.when(
                        data: (isPremium) {
                          return Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              subscribeButton(  // your styled LoginButtons version
                                context: context,
                                isPremium: isPremium,
                                churchId: auth.churchId!,
                              ),
                              // Explanatory text — ONLY shown if NOT premium
                              if (!isPremium) ...[
                                SizedBox(height: 16.sp),
                                Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 32.sp),
                                  child: Text(
                                    "All features work perfect without premium purchase!\n"
                                    "Premium exists to remove ads for your parish congregation!",
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 10.sp,
                                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                                    ),
                                  ),
                                ),
                              ],
                              SizedBox(height: 10.sp),
                            ],
                          );
                        },
                        loading: () => const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: CircularProgressIndicator(),
                        ),
                        error: (_, __) => Text(
                          "Could not load premium status",
                          style: TextStyle(color: Colors.red.shade700),
                        ),
                      );
                    },
                  ),
                  SizedBox(height: 15.sp),
                  if (context.watch<AuthService>().isGlobalAdmin)
                    ElevatedButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => SubscriptionScreen(churchId: auth.churchId!),
                          ),
                        );
                      },
                      child: const Text("Manage Church Settings"),
                    ),
                ],
              ),
            ),*/
          ],
        ),
      ),
    );
  }
}