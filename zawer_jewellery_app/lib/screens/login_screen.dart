import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../utils/text_styles.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/api_service.dart';
import '../utils/colors.dart';
import '../utils/validators.dart';
import 'forgot_password_screen.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final GlobalKey<FormState> _formKey =
  GlobalKey<FormState>();

  final TextEditingController emailController =
  TextEditingController();

  final TextEditingController passwordController =
  TextEditingController();

  bool hidePassword = true;
  bool rememberMe = false;
  bool isLoading = false;

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  // ==================================================
  // LOGIN USER
  // ==================================================

  Future<void> loginUser() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      isLoading = true;
    });

    try {
      final result = await ApiService.loginUser(
        email: emailController.text.trim(),
        password: passwordController.text,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        isLoading = false;
      });

      final bool success = result["success"] == true;

      // ==================================================
      // SUCCESS
      // ==================================================

      if (success) {
        final SharedPreferences prefs =
        await SharedPreferences.getInstance();

        final String token =
            result["token"]?.toString() ?? "";

        final dynamic userData = result["user"];

        // Save JWT token
        if (token.isNotEmpty) {
          await prefs.setString(
            "token",
            token,
          );
        }

        // Save user details
        if (userData is Map) {
          await prefs.setString(
            "userId",
            userData["id"]?.toString() ?? "",
          );

          await prefs.setString(
            "userName",
            userData["name"]?.toString() ?? "",
          );

          await prefs.setString(
            "userEmail",
            userData["email"]?.toString() ?? "",
          );

          await prefs.setString(
            "userPhone",
            userData["phone"]?.toString() ?? "",
          );

          await prefs.setString(
            "userRole",
            userData["role"]?.toString() ?? "user",
          );
        }

        // Remember Me
        await prefs.setBool(
          "rememberMe",
          rememberMe,
        );

        if (!mounted) {
          return;
        }

        // Success message
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "Login successful!",
            ),
            backgroundColor: Colors.green,
          ),
        );

        // Pushed from inside the app: return there. Root: go to Bottom Navigation.
        if (Navigator.canPop(context)) {
          Navigator.pop(context, true);
        } else {
          Navigator.pushReplacementNamed(
            context,
            "/bottomNav",
          );
        }

        return;
      }

      // ==================================================
      // LOGIN FAILED
      // ==================================================

      final String message =
          result["message"]?.toString() ??
              "Login failed";

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error.toString(),
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // ==================================================
  // BUILD
  // ==================================================

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: Navigator.of(context).canPop(),
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        SystemNavigator.pop();
      },
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,

        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: 25,
            ),

          child: Form(
            key: _formKey,

            child: Column(
              children: [

                const SizedBox(height: 45),

                // ==================================================
                // LOGO
                // ==================================================

                Container(
                  height: 120,
                  width: 120,

                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius:
                    BorderRadius.circular(30),

                    boxShadow: [
                      BoxShadow(
                        color:
                        Colors.black.withValues(
                          alpha: 0.08,
                        ),
                        blurRadius: 15,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),

                  child: Icon(
                    Icons.diamond,
                    size: 70,
                    color: AppColors.brand(context),
                  ),
                ),

                const SizedBox(height: 25),

                // ==================================================
                // BRAND
                // ==================================================

                Text(
                  "ZAWER",
                  style: AppFonts.cinzel(
                    fontSize: 42,
                    color: AppColors.brand(context),
                    fontWeight: FontWeight.bold,
                    letterSpacing: 4,
                  ),
                ),

                const SizedBox(height: 10),

                Text(
                  "Luxury Jewellery Collection",
                  style: AppFonts.poppins(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 16,
                  ),
                ),

                const SizedBox(height: 40),

                // ==================================================
                // LOGIN CARD
                // ==================================================

                Container(
                  padding:
                  const EdgeInsets.all(25),

                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius:
                    BorderRadius.circular(25),

                    boxShadow: [
                      BoxShadow(
                        color:
                        Colors.black.withValues(
                          alpha: 0.05,
                        ),
                        blurRadius: 12,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),

                  child: Column(
                    children: [

                      // ==================================================
                      // EMAIL
                      // ==================================================

                      TextFormField(
                        controller:
                        emailController,

                        keyboardType:
                        TextInputType.emailAddress,

                        decoration:
                        InputDecoration(
                          labelText:
                          "Email Address",

                          hintText:
                          "Enter your email",

                          prefixIcon:
                          const Icon(
                            Icons.email_outlined,
                          ),

                          border:
                          OutlineInputBorder(
                            borderRadius:
                            BorderRadius.circular(
                              15,
                            ),
                          ),
                        ),

                        validator: (value) {
                          if (value == null ||
                              value.trim().isEmpty) {
                            return
                              "Please enter your email";
                          }

                          if (!isValidEmail(value)) {
                            return
                              "Enter a valid email";
                          }

                          return null;
                        },
                      ),

                      const SizedBox(height: 20),

                      // ==================================================
                      // PASSWORD
                      // ==================================================

                      TextFormField(
                        controller:
                        passwordController,

                        obscureText:
                        hidePassword,

                        decoration:
                        InputDecoration(
                          labelText: "Password",

                          hintText:
                          "Enter your password",

                          prefixIcon:
                          const Icon(
                            Icons.lock_outline,
                          ),

                          suffixIcon:
                          IconButton(
                            icon: Icon(
                              hidePassword
                                  ? Icons.visibility
                                  : Icons.visibility_off,
                            ),

                            onPressed: () {
                              setState(() {
                                hidePassword =
                                !hidePassword;
                              });
                            },
                          ),

                          border:
                          OutlineInputBorder(
                            borderRadius:
                            BorderRadius.circular(
                              15,
                            ),
                          ),
                        ),

                        validator: (value) {
                          if (value == null ||
                              value.isEmpty) {
                            return
                              "Password is required";
                          }

                          if (value.length < 6) {
                            return
                              "Password must contain at least 6 characters";
                          }

                          return null;
                        },
                      ),

                      const SizedBox(height: 18),

                      // ==================================================
                      // REMEMBER ME + FORGOT PASSWORD
                      // ==================================================

                      Row(
                        children: [

                          Checkbox(
                            value: rememberMe,

                            activeColor:
                            AppColors.primary,

                            onChanged:
                                (value) {
                              setState(() {
                                rememberMe =
                                    value ?? false;
                              });
                            },
                          ),

                          Text(
                            "Remember Me",
                            style:
                            AppFonts.poppins(
                              fontWeight:
                              FontWeight.w500,
                            ),
                          ),

                          const Spacer(),

                          TextButton(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                  const ForgotPasswordScreen(),
                                ),
                              );
                            },

                            child: Text(
                              "Forgot Password?",
                              style:
                              AppFonts.poppins(
                                color:
                                AppColors.brand(context),
                                fontWeight:
                                FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 20),

                      // ==================================================
                      // LOGIN BUTTON
                      // ==================================================

                      SizedBox(
                        width:
                        double.infinity,
                        height: 55,

                        child:
                        ElevatedButton(
                          style:
                          ElevatedButton.styleFrom(
                            backgroundColor:
                            AppColors.primary,

                            shape:
                            RoundedRectangleBorder(
                              borderRadius:
                              BorderRadius
                                  .circular(
                                15,
                              ),
                            ),
                          ),

                          onPressed:
                          isLoading
                              ? null
                              : loginUser,

                          child: isLoading
                              ? const SizedBox(
                            width: 25,
                            height: 25,

                            child:
                            CircularProgressIndicator(
                              color:
                              Colors.white,
                              strokeWidth: 3,
                            ),
                          )
                              : Text(
                            "LOGIN",

                            style:
                            AppFonts.cinzel(
                              fontSize: 18,
                              color:
                              Colors.white,
                              fontWeight:
                              FontWeight.bold,
                              letterSpacing: 2,
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 25),

                      // ==================================================
                      // OR
                      // ==================================================

                      Row(
                        children: [

                          Expanded(
                            child: Divider(
                              color:
                              Colors.grey.shade400,
                            ),
                          ),

                          Padding(
                            padding:
                            const EdgeInsets
                                .symmetric(
                              horizontal: 10,
                            ),

                            child: Text(
                              "OR",
                              style:
                              AppFonts.poppins(),
                            ),
                          ),

                          Expanded(
                            child: Divider(
                              color:
                              Colors.grey.shade400,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 25),

                      // ==================================================
                      // GOOGLE
                      // ==================================================

                      SizedBox(
                        width:
                        double.infinity,
                        height: 55,

                        child:
                        OutlinedButton.icon(
                          onPressed: () {
                            ScaffoldMessenger.of(
                              context,
                            ).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  "Google Sign-In Coming Soon",
                                ),
                              ),
                            );
                          },

                          icon: const Icon(
                            Icons.g_mobiledata,
                            color: Colors.red,
                            size: 35,
                          ),

                          label: Text(
                            "Continue with Google",
                            style:
                            AppFonts.poppins(
                              color: Theme.of(context).colorScheme.onSurface,
                              fontWeight:
                              FontWeight.w600,
                            ),
                          ),

                          style:
                          OutlinedButton.styleFrom(
                            side: BorderSide(
                              color:
                              Colors.grey.shade300,
                            ),

                            shape:
                            RoundedRectangleBorder(
                              borderRadius:
                              BorderRadius.circular(
                                15,
                              ),
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 15),

                      // ==================================================
                      // APPLE
                      // ==================================================

                      SizedBox(
                        width:
                        double.infinity,
                        height: 55,

                        child:
                        OutlinedButton.icon(
                          onPressed: () {
                            ScaffoldMessenger.of(
                              context,
                            ).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  "Apple Sign-In Coming Soon",
                                ),
                              ),
                            );
                          },

                          icon: Icon(
                            Icons.apple,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),

                          label: Text(
                            "Continue with Apple",
                            style:
                            AppFonts.poppins(
                              color: Theme.of(context).colorScheme.onSurface,
                              fontWeight:
                              FontWeight.w600,
                            ),
                          ),

                          style:
                          OutlinedButton.styleFrom(
                            side: BorderSide(
                              color:
                              Colors.grey.shade300,
                            ),

                            shape:
                            RoundedRectangleBorder(
                              borderRadius:
                              BorderRadius.circular(
                                15,
                              ),
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 20),

                      // ==================================================
                      // GUEST
                      // ==================================================

                      TextButton(
                        onPressed: () {
                          if (Navigator.canPop(context)) {
                            Navigator.pop(context);
                            return;
                          }
                          Navigator
                              .pushReplacementNamed(
                            context,
                            "/bottomNav",
                          );
                        },

                        child: Text(
                          "Continue as Guest",
                          style:
                          AppFonts.poppins(
                            color:
                            AppColors.brand(context),
                            fontWeight:
                            FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // ==================================================
                // REGISTER
                // ==================================================

                Row(
                  mainAxisAlignment:
                  MainAxisAlignment.center,

                  children: [

                    Text(
                      "Don't have an account?",
                      style:
                      AppFonts.poppins(
                        fontSize: 15,
                      ),
                    ),

                    TextButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                            const RegisterScreen(),
                          ),
                        );
                      },

                      child: Text(
                        "Register",
                        style:
                        AppFonts.poppins(
                          color:
                          AppColors.brand(context),
                          fontWeight:
                          FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                // ==================================================
                // FOOTER
                // ==================================================

                Text(
                  "Luxury Jewellery Since 2026",
                  textAlign: TextAlign.center,

                  style: AppFonts.cormorantGaramond(
                    fontSize: 20,
                    fontStyle:
                    FontStyle.italic,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),

                const SizedBox(height: 15),

              ],
            ),
          ),
        ),
      ),
    ),
  );
}
}