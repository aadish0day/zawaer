import 'package:flutter/material.dart';
import '../utils/text_styles.dart';

import '../services/api_service.dart';
import '../utils/colors.dart';
import '../utils/validators.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final GlobalKey<FormState> formKey = GlobalKey<FormState>();

  final TextEditingController nameController =
  TextEditingController();

  final TextEditingController emailController =
  TextEditingController();

  final TextEditingController phoneController =
  TextEditingController();

  final TextEditingController passwordController =
  TextEditingController();

  final TextEditingController confirmPasswordController =
  TextEditingController();

  bool hidePassword = true;
  bool hideConfirmPassword = true;
  bool agreeTerms = false;
  bool isLoading = false;

  @override
  void dispose() {
    nameController.dispose();
    emailController.dispose();
    phoneController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> registerUser() async {
    if (!formKey.currentState!.validate()) {
      return;
    }

    if (!agreeTerms) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Please accept Terms & Conditions",
          ),
        ),
      );
      return;
    }

    setState(() {
      isLoading = true;
    });

    try {
      final result = await ApiService.registerUser(
        name: nameController.text.trim(),
        email: emailController.text.trim(),
        phone: phoneController.text.trim(),
        password: passwordController.text,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        isLoading = false;
      });

      final bool success = result["success"] == true;

      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "Account created successfully!",
            ),
            backgroundColor: Colors.green,
          ),
        );

        // Clear fields
        nameController.clear();
        emailController.clear();
        phoneController.clear();
        passwordController.clear();
        confirmPasswordController.clear();

        setState(() {
          agreeTerms = false;
        });

        // Return to login screen
        Navigator.pop(context);
      } else {
        final String message =
            result["message"]?.toString() ??
                "Registration failed";

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: Colors.red,
          ),
        );
      }
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
            "Something went wrong: $error",
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,

      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(25),

          child: Form(
            key: formKey,

            child: Column(
              children: [

                const SizedBox(height: 20),

                // =========================
                // LOGO
                // =========================

                Container(
                  height: 110,
                  width: 110,

                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius:
                    BorderRadius.circular(30),

                    boxShadow: [
                      BoxShadow(
                        color:
                        Colors.black.withValues(alpha: 0.08),
                        blurRadius: 12,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),

                  child: Icon(
                    Icons.diamond,
                    size: 70,
                    color: AppColors.brand(context),
                  ),
                ),

                const SizedBox(height: 20),

                // =========================
                // TITLE
                // =========================

                Text(
                  "CREATE ACCOUNT",
                  textAlign: TextAlign.center,

                  style: AppFonts.cinzel(
                    fontSize: 30,
                    fontWeight: FontWeight.bold,
                    color: AppColors.brand(context),
                    letterSpacing: 2,
                  ),
                ),

                const SizedBox(height: 8),

                Text(
                  "Join the Luxury Jewellery Experience",
                  textAlign: TextAlign.center,

                  style: AppFonts.poppins(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),

                const SizedBox(height: 35),

                // =========================
                // FORM CONTAINER
                // =========================

                Container(
                  padding: const EdgeInsets.all(22),

                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius:
                    BorderRadius.circular(25),

                    boxShadow: [
                      BoxShadow(
                        color:
                        Colors.black.withValues(alpha: 0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),

                  child: Column(
                    children: [

                      // FULL NAME
                      TextFormField(
                        controller: nameController,

                        maxLength: maxNameLength,

                        textCapitalization:
                        TextCapitalization.words,

                        decoration: InputDecoration(
                          labelText: "Full Name",
                          hintText:
                          "Enter your full name",
                          prefixIcon: const Icon(
                            Icons.person_outline,
                          ),
                          counterText: "",
                          border: OutlineInputBorder(
                            borderRadius:
                            BorderRadius.circular(15),
                          ),
                        ),

                        validator: (value) {
                          if (value == null ||
                              value.trim().isEmpty) {
                            return "Please enter your full name";
                          }

                          if (value.trim().length < 2) {
                            return "Enter a valid name";
                          }

                          return null;
                        },
                      ),

                      const SizedBox(height: 18),

                      // EMAIL
                      TextFormField(
                        controller: emailController,

                        maxLength: maxEmailLength,

                        keyboardType:
                        TextInputType.emailAddress,

                        decoration: InputDecoration(
                          labelText: "Email",
                          hintText:
                          "Enter your email",
                          prefixIcon: const Icon(
                            Icons.email_outlined,
                          ),
                          counterText: "",
                          border: OutlineInputBorder(
                            borderRadius:
                            BorderRadius.circular(15),
                          ),
                        ),

                        validator: (value) {
                          if (value == null ||
                              value.trim().isEmpty) {
                            return "Please enter your email";
                          }

                          if (!isValidEmail(value)) {
                            return "Enter a valid email";
                          }

                          return null;
                        },
                      ),

                      const SizedBox(height: 18),

                      // PHONE
                      TextFormField(
                        controller: phoneController,

                        keyboardType:
                        TextInputType.phone,

                        maxLength: maxPhoneLength,

                        decoration: InputDecoration(
                          labelText: "Phone Number (optional)",
                          hintText:
                          "Enter your phone number",
                          prefixIcon: const Icon(
                            Icons.phone_outlined,
                          ),
                          counterText: "",
                          border: OutlineInputBorder(
                            borderRadius:
                            BorderRadius.circular(15),
                          ),
                        ),

                        validator: (value) {
                          if (value == null ||
                              value.trim().isEmpty) {
                            return null;
                          }

                          if (!isValidPhone(value)) {
                            return "Enter a valid phone number";
                          }

                          return null;
                        },
                      ),

                      const SizedBox(height: 18),

                      // PASSWORD
                      TextFormField(
                        controller:
                        passwordController,

                        obscureText: hidePassword,

                        maxLength: maxPasswordLength,

                        decoration: InputDecoration(
                          labelText: "Password",
                          hintText:
                          "Create a password",

                          prefixIcon: const Icon(
                            Icons.lock_outline,
                          ),
                          counterText: "",

                          suffixIcon: IconButton(
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

                          border: OutlineInputBorder(
                            borderRadius:
                            BorderRadius.circular(15),
                          ),
                        ),

                        validator: (value) {
                          if (value == null ||
                              value.isEmpty) {
                            return "Password is required";
                          }

                          if (value.length < minPasswordLength) {
                            return "Password should contain at least 6 characters";
                          }

                          return null;
                        },
                      ),

                      const SizedBox(height: 18),

                      // CONFIRM PASSWORD
                      TextFormField(
                        controller:
                        confirmPasswordController,

                        obscureText:
                        hideConfirmPassword,

                        decoration: InputDecoration(
                          labelText:
                          "Confirm Password",
                          hintText:
                          "Re-enter password",

                          prefixIcon: const Icon(
                            Icons.lock_outline,
                          ),

                          suffixIcon: IconButton(
                            icon: Icon(
                              hideConfirmPassword
                                  ? Icons.visibility
                                  : Icons.visibility_off,
                            ),

                            onPressed: () {
                              setState(() {
                                hideConfirmPassword =
                                !hideConfirmPassword;
                              });
                            },
                          ),

                          border: OutlineInputBorder(
                            borderRadius:
                            BorderRadius.circular(15),
                          ),
                        ),

                        validator: (value) {
                          if (value == null ||
                              value.isEmpty) {
                            return "Please confirm your password";
                          }

                          if (value !=
                              passwordController.text) {
                            return "Passwords do not match";
                          }

                          return null;
                        },
                      ),

                      const SizedBox(height: 20),

                      // TERMS
                      Row(
                        crossAxisAlignment:
                        CrossAxisAlignment.start,

                        children: [

                          Checkbox(
                            value: agreeTerms,

                            activeColor:
                            AppColors.primary,

                            onChanged: (value) {
                              setState(() {
                                agreeTerms =
                                    value ?? false;
                              });
                            },
                          ),

                          const Expanded(
                            child: Padding(
                              padding:
                              EdgeInsets.only(top: 12),

                              child: Text(
                                "I agree to the Terms & Conditions",
                                style: TextStyle(
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 20),

                      // REGISTER BUTTON
                      SizedBox(
                        width: double.infinity,
                        height: 55,

                        child: ElevatedButton(
                          onPressed:
                          isLoading
                              ? null
                              : registerUser,

                          style:
                          ElevatedButton.styleFrom(
                            backgroundColor:
                            AppColors.primary,

                            shape:
                            RoundedRectangleBorder(
                              borderRadius:
                              BorderRadius.circular(15),
                            ),
                          ),

                          child: isLoading
                              ? const SizedBox(
                            height: 24,
                            width: 24,

                            child:
                            CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 3,
                            ),
                          )
                              : Text(
                            "REGISTER",

                            style:
                            AppFonts.cinzel(
                              fontSize: 18,
                              fontWeight:
                              FontWeight.bold,
                              letterSpacing: 2,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 25),

                // LOGIN
                Row(
                  mainAxisAlignment:
                  MainAxisAlignment.center,

                  children: [

                    Text(
                      "Already have an account?",
                      style:
                      AppFonts.poppins(),
                    ),

                    TextButton(
                      onPressed: () {
                        Navigator.pop(context);
                      },

                      child: Text(
                        "Login",

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

                Text(
                  "Luxury Jewellery Since 2026",

                  textAlign: TextAlign.center,

                  style:
                  AppFonts.cormorantGaramond(
                    fontSize: 18,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontStyle:
                    FontStyle.italic,
                  ),
                ),

                const SizedBox(height: 30),
              ],
            ),
          ),
        ),
      ),
    );
  }
}