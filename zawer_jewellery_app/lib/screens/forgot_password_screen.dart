import 'package:flutter/material.dart';
import '../utils/text_styles.dart';

import '../services/api_service.dart';

import '../utils/colors.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState
    extends State<ForgotPasswordScreen> {

  final formKey = GlobalKey<FormState>();

  final emailController = TextEditingController();

  final otpController = TextEditingController();

  final passwordController = TextEditingController();

  final confirmPasswordController =
  TextEditingController();

  bool isLoading = false;

  bool otpSent = false;

  @override
  void dispose() {
    emailController.dispose();

    otpController.dispose();

    passwordController.dispose();

    confirmPasswordController.dispose();

    super.dispose();
  }

  // =====================================================
  // STEP 1: SEND OTP
  // =====================================================

  Future<void> sendOTP() async {

    if (!formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      isLoading = true;
    });

    final result = await ApiService.forgotPassword(
      emailController.text.trim(),
    );

    if (!mounted) return;

    setState(() {
      isLoading = false;
    });

    if (result["success"] == true) {

      setState(() {
        otpSent = true;
      });

      final String otpMessage = result["devOtp"] != null
          ? "OTP sent (Dev code: ${result["devOtp"]})"
          : (result["message"]?.toString() ?? "OTP sent to your email");

      ScaffoldMessenger.of(context).showSnackBar(

        SnackBar(

          backgroundColor: Colors.green,

          content: Text(
            otpMessage,
          ),

        ),

      );

    } else {

      ScaffoldMessenger.of(context).showSnackBar(

        SnackBar(

          backgroundColor: Colors.red,

          content: Text(
            result["message"]?.toString() ??
                "Could not send OTP",
          ),

        ),

      );
    }
  }

  // =====================================================
  // STEP 2: RESET PASSWORD
  // =====================================================

  Future<void> resetPassword() async {

    if (!formKey.currentState!.validate()) {
      return;
    }

    if (passwordController.text !=
        confirmPasswordController.text) {

      ScaffoldMessenger.of(context).showSnackBar(

        const SnackBar(
          backgroundColor: Colors.red,
          content:
          Text("Passwords do not match"),
        ),

      );
      return;
    }

    setState(() {
      isLoading = true;
    });

    final result = await ApiService.resetPassword(
      email: emailController.text.trim(),
      otp: otpController.text.trim(),
      newPassword: passwordController.text,
    );

    if (!mounted) return;

    setState(() {
      isLoading = false;
    });

    if (result["success"] == true) {

      ScaffoldMessenger.of(context).showSnackBar(

        SnackBar(
          backgroundColor: Colors.green,
          content: Text(
            result["message"]?.toString() ??
                "Password reset successful",
          ),
        ),

      );

      Navigator.pop(context);

    } else {

      ScaffoldMessenger.of(context).showSnackBar(

        SnackBar(
          backgroundColor: Colors.red,
          content: Text(
            result["message"]?.toString() ??
                "Could not reset password",
          ),
        ),

      );
    }
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(

      backgroundColor:
      Theme.of(context).scaffoldBackgroundColor,

      appBar: otpSent
          ? AppBar(
        backgroundColor:
        Theme.of(context).colorScheme.surface,
        elevation: 0,
        iconTheme: IconThemeData(
          color: Theme.of(context)
              .colorScheme.onSurface,
        ),
      )
          : null,

      body: SafeArea(

        child: SingleChildScrollView(

          padding: const EdgeInsets.all(25),

          child: Form(

            key: formKey,

            child: Column(

              children: [

                if (!otpSent)
                  const SizedBox(height:40),

                Container(

                  height:110,

                  width:110,

                  decoration: BoxDecoration(

                    color:
                    Theme.of(context).colorScheme.surface,

                    borderRadius:
                    BorderRadius.circular(30),

                    boxShadow: [

                      BoxShadow(

                        color: Colors.black
                            .withValues(alpha: .08),

                        blurRadius:12,

                      ),

                    ],

                  ),

                  child: Icon(

                    otpSent
                        ? Icons.password
                        : Icons.lock_reset,

                    size:65,

                    color: AppColors.brand(context),

                  ),

                ),

                const SizedBox(height:20),

                Text(

                  otpSent
                      ? "Reset Password"
                      : "Forgot Password",

                  style: AppFonts.cinzel(

                    fontSize:30,

                    fontWeight: FontWeight.bold,

                    color: AppColors.brand(context),

                  ),

                ),

                const SizedBox(height:10),

                Text(

                  otpSent
                      ? "Enter the OTP and your new password"
                      : "Enter your email to receive an OTP",

                  style: AppFonts.poppins(

                    color: Theme.of(context)
                        .colorScheme.onSurfaceVariant,

                  ),

                ),

                const SizedBox(height:35),

                Container(

                  padding: const EdgeInsets.all(22),

                  decoration: BoxDecoration(

                    color:
                    Theme.of(context).colorScheme.surface,

                    borderRadius:
                    BorderRadius.circular(25),

                    boxShadow: [

                      BoxShadow(

                        color: Colors.black
                            .withValues(alpha: .05),

                        blurRadius:10,

                      ),

                    ],

                  ),

                  child: Column(

                    children: [

                      if (!otpSent) ...[

                        TextFormField(

                          controller: emailController,

                          keyboardType:
                          TextInputType.emailAddress,

                          decoration:
                          const InputDecoration(

                            labelText: "Email Address",

                            hintText:
                            "Enter your registered email",

                            prefixIcon:
                            Icon(Icons.email_outlined),

                          ),

                          validator: (value) {

                            if(value==null||
                                value.isEmpty){

                              return "Enter Email";

                            }

                            if(!value.contains("@")){

                              return "Enter Valid Email";

                            }

                            return null;

                          },

                        ),

                        const SizedBox(height:25),
                      ]

                      else ...[

                        TextFormField(

                          controller: emailController,

                          enabled: false,

                          keyboardType:
                          TextInputType.emailAddress,

                          decoration:
                          const InputDecoration(

                            labelText: "Email Address",

                            prefixIcon:
                            Icon(Icons.email_outlined),

                          ),

                        ),

                        const SizedBox(height:18),

                        TextFormField(

                          controller: otpController,

                          keyboardType: TextInputType.number,

                          maxLength: 6,

                          decoration:
                          const InputDecoration(

                            labelText: "Enter OTP",

                            hintText: "6-digit code",

                            prefixIcon:
                            Icon(Icons.pin),

                            counterText: "",

                          ),

                          validator: (value) {

                            if (value == null ||
                                value.isEmpty) {

                              return "Enter OTP";

                            }

                            if (value.length != 6) {

                              return "OTP must be 6 digits";

                            }

                            return null;

                          },

                        ),

                        const SizedBox(height:18),

                        TextFormField(

                          controller: passwordController,

                          obscureText: true,

                          decoration:
                          const InputDecoration(

                            labelText:
                            "New Password",

                            prefixIcon:
                            Icon(Icons.lock_outline),

                          ),

                          validator: (value) {

                            if (value == null ||
                                value.isEmpty) {

                              return "Enter New Password";

                            }

                            if (value.length < 6) {

                              return "Minimum 6 characters";

                            }

                            return null;

                          },

                        ),

                        const SizedBox(height:18),

                        TextFormField(

                          controller:
                          confirmPasswordController,

                          obscureText: true,

                          decoration:
                          const InputDecoration(

                            labelText:
                            "Confirm Password",

                            prefixIcon:
                            Icon(Icons.lock_outline),

                          ),

                          validator: (value) {

                            if (value == null ||
                                value.isEmpty) {

                              return "Confirm Password";

                            }

                            return null;

                          },

                        ),

                        const SizedBox(height:25),
                      ],

                      SizedBox(

                        width: double.infinity,

                        height:55,

                        child: ElevatedButton(

                          onPressed: isLoading
                              ? null
                              : (otpSent
                              ? resetPassword
                              : sendOTP),

                          child: isLoading

                              ? const CircularProgressIndicator(
                            color: Colors.white,
                          )

                              : Text(

                            otpSent
                                ? "RESET PASSWORD"
                                : "SEND OTP",

                            style:
                            AppFonts.cinzel(

                              fontSize:18,

                              fontWeight:
                              FontWeight.bold,

                            ),

                          ),

                        ),

                      ),

                      const SizedBox(height:20),

                      TextButton(

                        onPressed: (){

                          Navigator.pop(context);

                        },

                        child: Text(

                          "Back to Login",

                          style: AppFonts.poppins(

                            color:
                            AppColors.brand(context),

                            fontWeight:
                            FontWeight.bold,

                          ),

                        ),

                      ),

                    ],

                  ),

                ),

              ],

            ),

          ),

        ),

      ),

    );

  }

}
