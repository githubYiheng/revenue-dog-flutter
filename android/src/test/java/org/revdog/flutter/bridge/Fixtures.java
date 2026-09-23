package org.revdog.flutter.bridge;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertTrue;
import static org.junit.Assert.fail;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.File;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.Iterator;
import java.util.List;
import java.util.Map;
import java.util.TreeSet;

/**
 * 三方对账 fixture（{@code sdk/flutter/test/fixtures}，设计 §7）的读取与深度比较。
 *
 * 路径：Gradle 传的系统属性 {@code revdog.fixturesDir}（绝对路径）优先，否则相对模块目录 {@code ../test/fixtures}。
 * 比较：org.json 解析期望值 → Java 值；map 键集必须相等（含值为 null 的键）；数值一律按 long 比；列表按序比。
 */
final class Fixtures {

    private Fixtures() {
    }

    static File dir() {
        String property = System.getProperty("revdog.fixturesDir");
        File dir = property != null ? new File(property) : new File("../test/fixtures");
        assertTrue("fixtures dir not found: " + dir.getAbsolutePath(), dir.isDirectory());
        return dir;
    }

    /** {@code sdk/flutter}（fixtures 的上两级），用于对照 Dart 源码里的表。 */
    static File packageRoot() {
        return dir().getAbsoluteFile().getParentFile().getParentFile();
    }

    static String read(String relativePath) {
        return read(new File(dir(), relativePath));
    }

    static String read(File file) {
        try {
            return new String(Files.readAllBytes(file.toPath()), StandardCharsets.UTF_8);
        } catch (IOException e) {
            throw new AssertionError("cannot read " + file, e);
        }
    }

    /** JSON 文本 → Java 值（Map / List / Long / Double / Boolean / String / null）。 */
    static Object parse(String json) {
        String trimmed = json.trim();
        try {
            return toJava(trimmed.startsWith("[") ? new JSONArray(trimmed) : new JSONObject(trimmed));
        } catch (Exception e) {
            // 编译期看到的是 android.jar 的 org.json（JSONException 为受检异常），运行期是 org.json:json。
            throw new AssertionError("invalid fixture JSON", e);
        }
    }

    private static Object toJava(Object value) throws Exception {
        if (value == JSONObject.NULL || value == null) {
            return null;
        }
        if (value instanceof JSONObject) {
            JSONObject object = (JSONObject) value;
            Map<String, Object> map = new HashMap<>();
            Iterator<String> keys = object.keys();
            while (keys.hasNext()) {
                String key = keys.next();
                map.put(key, toJava(object.get(key)));
            }
            return map;
        }
        if (value instanceof JSONArray) {
            JSONArray array = (JSONArray) value;
            List<Object> list = new ArrayList<>();
            for (int i = 0; i < array.length(); i++) {
                list.add(toJava(array.get(i)));
            }
            return list;
        }
        return value;
    }

    static void assertDeepEquals(Object expected, Object actual) {
        assertDeepEquals("$", expected, actual);
    }

    private static void assertDeepEquals(String path, Object expected, Object actual) {
        if (expected == null || actual == null) {
            assertEquals(path, expected, actual);
            return;
        }
        if (expected instanceof Map) {
            if (!(actual instanceof Map)) {
                fail(path + ": expected map, got " + actual.getClass().getSimpleName() + " " + actual);
            }
            Map<?, ?> e = (Map<?, ?>) expected;
            Map<?, ?> a = (Map<?, ?>) actual;
            assertEquals(path + " keys", new TreeSet<>(stringKeys(e)), new TreeSet<>(stringKeys(a)));
            for (Object key : e.keySet()) {
                assertDeepEquals(path + "." + key, e.get(key), a.get(key));
            }
            return;
        }
        if (expected instanceof List) {
            if (!(actual instanceof List)) {
                fail(path + ": expected list, got " + actual.getClass().getSimpleName() + " " + actual);
            }
            List<?> e = (List<?>) expected;
            List<?> a = (List<?>) actual;
            assertEquals(path + " size", e.size(), a.size());
            for (int i = 0; i < e.size(); i++) {
                assertDeepEquals(path + "[" + i + "]", e.get(i), a.get(i));
            }
            return;
        }
        if (expected instanceof Number) {
            if (!(actual instanceof Number)) {
                fail(path + ": expected number " + expected + ", got " + actual.getClass().getSimpleName() + " " + actual);
            }
            assertEquals(path, ((Number) expected).longValue(), ((Number) actual).longValue());
            // 时间必须是 Long（int64），int 在 Dart 侧同为 int，但契约写的是 epoch 毫秒 Long。
            return;
        }
        assertEquals(path + " type", expected.getClass(), actual.getClass());
        assertEquals(path, expected, actual);
    }

    private static List<String> stringKeys(Map<?, ?> map) {
        List<String> keys = new ArrayList<>();
        for (Object key : map.keySet()) {
            keys.add(String.valueOf(key));
        }
        return keys;
    }
}
