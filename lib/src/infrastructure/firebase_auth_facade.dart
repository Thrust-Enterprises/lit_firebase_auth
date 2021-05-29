import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_oauth/firebase_auth_oauth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:meta/meta.dart';

import '../domain/auth/auth.dart';
import '../domain/auth/auth_failure.dart';
import '../domain/auth/exceptions.dart';
import '../domain/auth/i_auth_facade.dart';
import '../domain/auth/user.dart';
import '../domain/auth/value_objects.dart';

class FirebaseAuthFacade implements AuthFacade {
  final FirebaseAuth _firebaseAuth;
  final GoogleSignIn _googleSignIn;
  final FacebookAuth _facebookAuth;
  final FirebaseApp _app;
  final bool googleSignInEnabled;
  final bool facebookSignInEnabled;

  FirebaseAuthFacade({
    FirebaseAuth firebaseAuth,
    GoogleSignIn googleSignIn,
    FacebookAuth facebookAuth,
    FirebaseApp app,
    this.googleSignInEnabled = false,
    this.facebookSignInEnabled = false,
  })  : _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance,
        _googleSignIn = googleSignIn ?? GoogleSignIn(),
        _facebookAuth = facebookAuth ?? FacebookAuth.instance,
        _app = app ?? Firebase.app();


  @override
  LitUser getSignedInUser() => _mapUser(_firebaseAuth.currentUser);

  @override
  Stream<LitUser> get onAuthStateChanged {
    return _firebaseAuth.authStateChanges().map(_mapUser);
  }

  LitUser _mapUser(User user) {
    if (user == null) {
      return const LitUser.empty();
    }
    return LitUser(user: user);
  }

  @override
  Future<Auth> registerWithEmailAndPassword({
    @required EmailAddress emailAddress,
    @required Password password,
  }) async {
    final emailAddressStr = emailAddress.getOrCrash();
    final passwordStr = password.getOrCrash();
    if (kIsWeb) {
      return _webRegisterWithEmailAndPassword(
        email: emailAddressStr,
        password: passwordStr,
      );
    } else {
      return _registerWithEmailAndPassword(
        email: emailAddressStr,
        password: passwordStr,
      );
    }
  }

  @override
  Future<Auth> registerWithCellphoneNumber({
    @required CellphoneNumber cellphoneNumber,
  }) async {
    final cellphoneStr = cellphoneNumber.getOrCrash();
    return _registerWithCellphoneNumber(
      cellphoneNumber: cellphoneStr
    );
  }

  Future<Auth> _webRegisterWithEmailAndPassword(
      {String email, String password}) async {
    try {
      await _firebaseAuth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      return const Auth.success();
    } catch (e) {
      debugPrint(e.code);
      switch (e.code) {
        case "auth/email-already-in-use":
          return const Auth.failure(AuthFailure.emailAlreadyInUse());
          break;
        default:
          debugPrint(e.toString());
          return const Auth.failure(AuthFailure.serverError());
      }
    }
  }

  Future<Auth> _registerWithEmailAndPassword(
      {String email, String password}) async {
    try {
      await _firebaseAuth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      return const Auth.success();
    } on PlatformException catch (e) {
      if (e.code == 'ERROR_EMAIL_ALREADY_IN_USE') {
        return const Auth.failure(AuthFailure.emailAlreadyInUse());
      } else {
        debugPrint(e.toString());
        return const Auth.failure(AuthFailure.serverError());
      }
    }
  }

  Future<Auth> _registerWithCellphoneNumber(
      {String cellphoneNumber}) async {
    try {
      await _firebaseAuth.verifyPhoneNumber(
        phoneNumber: cellphoneNumber,
        verificationCompleted: (PhoneAuthCredential credential) {},
        verificationFailed: (FirebaseAuthException e) {},
        codeSent: (String verificationId, int resendToken) {},
        codeAutoRetrievalTimeout: (String verificationId) {},
      );
      return const Auth.success();
    } on PlatformException catch (e) {
      debugPrint(e.toString());
      return const Auth.failure(AuthFailure.serverError());
    }
  }

  @override
  Future<Auth> signInWithEmailAndPassword({
    @required EmailAddress emailAddress,
    @required Password password,
  }) async {
    final emailAddressStr = emailAddress.getOrCrash();
    final passwordStr = password.getOrCrash();
    try {
      await _firebaseAuth.signInWithEmailAndPassword(
        email: emailAddressStr,
        password: passwordStr,
      );
      return const Auth.success();
    } on FirebaseAuthException catch (e) {
      switch (e.code) {
        case "wrong-password":
        case "user-not-found":
          return const Auth.failure(
            AuthFailure.invalidEmailAndPasswordCombination(),
          );
          break;
        case "invalid-email":
          return const Auth.failure(AuthFailure.malformed());
          break;
        case "user-disabled":
          return const Auth.failure(AuthFailure.userDisabled());
          break;
        case "too-many-requests":
          return const Auth.failure(AuthFailure.tooManyRequests());
          break;
        default:
          debugPrint(e.toString());
          return const Auth.failure(AuthFailure.serverError());
      }
    }
  }

  @override
  Future<Auth> signInWithGoogle() async {
    if (!googleSignInEnabled) {
      throw AuthProviderNotEnabled('Google');
    }

    if (kIsWeb) {
      return _webSignInWithGoogle();
    } else {
      return _signInWithGoogle();
    }
  }

  Future<Auth> _webSignInWithGoogle() async {
    // TODO investigate alternative solutions to handle these exceptions
    // Will possibly be solved once the Firebase Auth rework is complete
    // See: https://github.com/FirebaseExtended/flutterfire/issues/2582
    GoogleSignInAccount googleUser;
    try {
      googleUser = await _googleSignIn.signInSilently();
    } catch (e) {
      if (e.toString().contains('appClientId != null')) {
        debugPrint(e);
        return const Auth.failure(AuthFailure.serverError());
      }
      return const Auth.failure(AuthFailure.cancelledByUser());
    }
    try {
      final googleAuthentication = await googleUser.authentication;

      final authCredential = GoogleAuthProvider.credential(
        idToken: googleAuthentication.idToken,
        accessToken: googleAuthentication.accessToken,
      );

      await _firebaseAuth.signInWithCredential(authCredential);
      return const Auth.success();
    } catch (e) {
      debugPrint(e);
      return const Auth.failure(AuthFailure.serverError());
    }
  }

  Future<Auth> _signInWithGoogle() async {
    try {
      print ("===BEFORE GOOGLE LOGIN");
      final googleUser = await _googleSignIn.signIn();
      print ("===AFTER GOOGLE LOGIN");
      if (googleUser == null) {
        print ("===GOOGLEUSER IS NULL");
        return const Auth.failure(AuthFailure.cancelledByUser());
      }

      final googleAuthentication = await googleUser.authentication;

      final authCredential = GoogleAuthProvider.credential(
        idToken: googleAuthentication.idToken,
        accessToken: googleAuthentication.accessToken,
      );

      await _firebaseAuth.signInWithCredential(authCredential);
      return const Auth.success();
    } catch (e) {
      debugPrint('===GOOGLE ERROR: ' + e.toString());
      print('===GOOGLE ERROR: ' + e.toString());
      return const Auth.failure(AuthFailure.serverError());
    }
  }

  @override
  Future<Auth> signInWithFacebook() async {
    try {
      // by default the login method has the next permissions ['email','public_profile']
      final LoginResult result = await FacebookAuth.instance.login();
      if (result.status == LoginStatus.success) {
        // you are logged
        final AccessToken accessToken = result.accessToken;
        final facebookAuth = FacebookAuthProvider.credential(accessToken.token);
        await _firebaseAuth.signInWithCredential(facebookAuth);
        return const Auth.success();
      }
    } catch (e, s) {
      print(e.errorCode + ' ' + e.message);
      return const Auth.failure(AuthFailure.serverError());
    }
  }

  @override
  Future<Auth> signInAnonymously() async {
    try {
      await _firebaseAuth.signInAnonymously();
      return const Auth.success();
    } on FirebaseAuthException catch (e) {
      debugPrint(e.toString());
      return const Auth.failure(AuthFailure.serverError());
    }
  }

  @override
  Future<Auth> signInWithCredential(AuthCredential credential) async {
    try {
      await _firebaseAuth.signInWithCredential(credential);
      return const Auth.success();
    } on FirebaseAuthException catch (e) {
      debugPrint(e.toString());
      return const Auth.failure(AuthFailure.serverError());
    } catch (e) {
      debugPrint(e.toString());
      return const Auth.failure(AuthFailure.serverError()); // todo improve
    }
  }

  @override
  Future<Auth> signInWithOAuth(String provider, List<String> scopes,
      Map<String, String> parameters) async {
    try {
      await FirebaseAuthOAuth(app: _app)
          .openSignInFlow(provider, scopes, parameters);
      return const Auth.success();
    } on PlatformException catch (e) {
      /**
       * The plugin has the following error codes:
       * 1. FirebaseAuthError: FirebaseAuth related error
       * 2. PlatformError: An platform related error
       * 3. PluginError: An error from this plugin
       */
      debugPrint("${e.code}: ${e.message}");
      if (e.message == 'The interaction was cancelled by the user.') {
        return const Auth.failure(AuthFailure.cancelledByUser());
      }
      return const Auth.failure(AuthFailure.serverError());
    } catch (e) {
      debugPrint(e.toString());
      if (e.toString().contains('auth/popup-closed-by-user')) {
        return const Auth.failure(AuthFailure.cancelledByUser());
      }
      debugPrint(e.toString());
      return const Auth.failure(AuthFailure.serverError());
    }
  }

  @override
  Future<void> signOut() async {
    return Future.wait([
      _signOutGoogle(),
      _firebaseAuth.signOut(),
    ]);
  }

  Future<void> _signOutGoogle() async {
    if (!googleSignInEnabled) return;
    try {
      await _googleSignIn.signOut();
    } catch (e) {
      rethrow;
    }
  }
}
