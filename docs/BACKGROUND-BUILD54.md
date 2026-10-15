# Muwa — приглушённый фон, Build 54

По замечанию владельца фон слишком яркий. Меняются параметры существующего
фона; цвета текста, кнопок и реальных обложек сохраняются.

- iOS/Android: общий множитель световых пятен 0.55 вместо1.0, то есть интенсивность
  снижена на45%. Позиции, размер и медленное движение пятен прежние; reduced-motion,
  энергосбережение и lifecycle-policy сохранены.
- iOS: размытый фон от обложки: saturation1.18→0.85, opacity0.54→0.34, чуть более
  тёмный верхний/средний градиент. Sharp foreground artwork и его загрузка/cache
  не меняются; дополнительный full-screen blur не добавляется.
- Android: существующий сплошной фон плеера использует общий тёмный цвет палитры.
- Геометрия бара, жесты, воспроизведение, субтитры, API и сохранённые ключи прежние.

## Рамки

Присланные репозитории: VoltAgent/awesome-claude-design — каталог ссылок;
Leonxlnx/taste-skill — конкретные рецепты поверхностей;
kylezantos/design-motion-principles — правила движения и производительности.

Самый прямой рецепт: [soft-skill §4A Double-Bezel](https://github.com/Leonxlnx/taste-skill/blob/main/skills/soft-skill/SKILL.md):
тонкий внешний корпус, отдельная внутренняя поверхность, inner radius равен outer
radius минус отступ. §4B предлагает отдельную круглую область для стрелки.
[Minimalist §5](https://github.com/Leonxlnx/taste-skill/blob/main/skills/minimalist-skill/SKILL.md)
полезен для сдержанных строк и разделителей.
[Motion cookbook](https://github.com/kylezantos/design-motion-principles/blob/main/skills/design-motion-principles/references/motion-cookbook.md)
помогает выбирать короткое нажатие и спокойный переход без отскока.

Подготовлены три самостоятельных примера: двойной контур, мягкая стеклянная
поверхность, тёмная поверхность с утопленной иконкой. Это примеры для сравнения,
а не native screenshots и не применённый новый дизайн. При выборе надо адаптировать
рецепт к SwiftUI/Compose, сохранить native typography, accessibility и утверждённый
бар. Не копировать React/Tailwind или полную веб-раскладку в нативный экран.
