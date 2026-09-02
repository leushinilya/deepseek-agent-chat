export const baseSystemPrompt = 'Ты полезный ИИ-ассистент. Отвечай ясно, точно и по делу на языке пользователя.';

export function explainedMessages(query) {
  return [{role: 'system', content: `${baseSystemPrompt}\nВерни JSON-объект с полями answer и reasoningSummary. reasoningSummary — краткое понятное объяснение ключевых шагов, допущений и оснований. Не раскрывай скрытую цепочку рассуждений или внутренние рассуждения модели.`}, {role: 'user', content: query}];
}

export function promptImprovementMessages(query) {
  return [{role: 'system', content: 'Преобразуй запрос пользователя в самодостаточный, точный и практичный промт, сохранив исходное намерение. Не отвечай на сам запрос. Верни JSON-объект только с полем generatedPrompt.'}, {role: 'user', content: query}];
}

export function roleMessages(query, roles) {
  return [{role: 'system', content: `${baseSystemPrompt}\nОтветь на исходный запрос отдельно с точки зрения каждой заданной роли. Не имитируй профессиональную лицензию и добавляй уместные оговорки для медицинских, юридических или финансовых тем. Верни JSON вида {"answers":[{"role":"точное название роли","answer":"ответ"}]}. Сохрани роли и их порядок: ${JSON.stringify(roles)}.`}, {role: 'user', content: query}];
}
