/// Простейшая локализация: строки пишем сразу на двух языках.
class L {
  static bool ru = true;
}

String tr(String ru, String en) => L.ru ? ru : en;
