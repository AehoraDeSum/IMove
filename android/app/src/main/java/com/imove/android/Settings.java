package com.imove.android;

import android.content.Context;
import android.content.SharedPreferences;
import android.security.keystore.KeyGenParameterSpec;
import android.security.keystore.KeyProperties;

import java.nio.charset.StandardCharsets;
import java.security.KeyStore;
import java.util.Base64;

import javax.crypto.Cipher;
import javax.crypto.KeyGenerator;
import javax.crypto.SecretKey;
import javax.crypto.spec.GCMParameterSpec;

final class Settings {
    private static final String NAME = "imove_private";
    private static final String URL = "url";
    private static final String TOKEN = "token";
    private static final String SEALED_TOKEN = "sealed_token";
    private static final String KEY_ALIAS = "imove_pairing_key";
    private static final String LAST_RESULT = "last_result";

    private static SharedPreferences prefs(Context context) {
        return context.getSharedPreferences(NAME, Context.MODE_PRIVATE);
    }

    static EndpointConfig load(Context context) {
        SharedPreferences p = prefs(context);
        return EndpointConfig.parse(p.getString(URL, ""), token(context));
    }

    static void save(Context context, EndpointConfig config) {
        try {
            prefs(context).edit().putString(URL, config.baseUrl)
                    .putString(SEALED_TOKEN, seal(config.token)).remove(TOKEN).apply();
        } catch (Exception error) {
            throw new IllegalStateException("Could not save the pairing code to secure storage.", error);
        }
    }

    static String url(Context context) { return prefs(context).getString(URL, ""); }
    static String token(Context context) {
        SharedPreferences p = prefs(context);
        String sealed = p.getString(SEALED_TOKEN, "");
        if (!sealed.isEmpty()) {
            try { return unseal(sealed); }
            catch (Exception error) { return ""; }
        }
        String legacy = p.getString(TOKEN, "");
        if (!legacy.isEmpty()) {
            try {
                p.edit().putString(SEALED_TOKEN, seal(legacy)).remove(TOKEN).apply();
            } catch (Exception error) { return ""; }
        }
        return legacy;
    }
    static void signOut(Context context) {
        prefs(context).edit().remove(TOKEN).remove(SEALED_TOKEN).apply();
    }
    static String lastResult(Context context) { return prefs(context).getString(LAST_RESULT, "Nothing sent yet."); }
    static void setLastResult(Context context, String result) {
        prefs(context).edit().putString(LAST_RESULT, result).apply();
    }

    private static SecretKey key() throws Exception {
        KeyStore store = KeyStore.getInstance("AndroidKeyStore");
        store.load(null);
        SecretKey existing = (SecretKey) store.getKey(KEY_ALIAS, null);
        if (existing != null) return existing;
        KeyGenerator generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore");
        generator.init(new KeyGenParameterSpec.Builder(KEY_ALIAS,
                KeyProperties.PURPOSE_ENCRYPT | KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build());
        return generator.generateKey();
    }

    private static String seal(String value) throws Exception {
        Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
        cipher.init(Cipher.ENCRYPT_MODE, key());
        byte[] iv = cipher.getIV();
        byte[] encrypted = cipher.doFinal(value.getBytes(StandardCharsets.UTF_8));
        return Base64.getEncoder().encodeToString(iv) + ":" + Base64.getEncoder().encodeToString(encrypted);
    }

    private static String unseal(String value) throws Exception {
        String[] parts = value.split(":", 2);
        if (parts.length != 2) return "";
        Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
        cipher.init(Cipher.DECRYPT_MODE, key(),
                new GCMParameterSpec(128, Base64.getDecoder().decode(parts[0])));
        return new String(cipher.doFinal(Base64.getDecoder().decode(parts[1])), StandardCharsets.UTF_8);
    }
}
