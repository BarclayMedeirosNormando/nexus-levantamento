import 'database.dart';

class ServidorAssinante {
  final String matricula;
  final String nome;
  const ServidorAssinante({required this.matricula, required this.nome});

  factory ServidorAssinante.fromRow(Map<String, Object?> row) {
    return ServidorAssinante(
      matricula: row['matricula'] as String,
      nome: row['nome'] as String? ?? row['matricula'] as String,
    );
  }
}

/// SERVIDORES é referência (populada em `pull_referencia`, ~26-29 mil
/// linhas — ver §10 do spec). Único uso hoje fora do login: a Tela 8
/// (Conclusão) só deixa escolher, como responsável pela assinatura, um
/// servidor com `PODE_ASSINAR=true` — mesma regra que o backend confere de
/// novo (redundante de propósito) em `actionPushLevantamento`.
class ServidoresRepository {
  Future<List<ServidorAssinante>> listarAssinantes() async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      'servidores',
      where: 'pode_assinar = 1',
      orderBy: 'nome ASC',
    );
    return rows.map(ServidorAssinante.fromRow).toList();
  }
}
