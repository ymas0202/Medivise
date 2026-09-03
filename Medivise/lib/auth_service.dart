class AuthService {
  static String? _authToken;
  
  static void setToken(String token) {
    _authToken = token;
    print('🔐 AuthService: Token stored');
  }
  
  static String? getToken() {
    print('🔐 AuthService: Token retrieved - exists: ${_authToken != null}');
    return _authToken;
  }
  
  static void clearToken() {
    _authToken = null;
    print('🔐 AuthService: Token cleared');
  }
}