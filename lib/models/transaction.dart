class Transaction {
  final String id;
  final TransactionType type;
  final DateTime date;
  final String? description;
  final double amount;
  final TransactionCategory category;
  
  // Novos campos para salário
  final bool isSalary;
  final SalaryAllocation? salaryAllocation; // null se não for salário
  
  // Novo campo para categorização de despesas
  final ExpenseBudgetCategory? expenseBudgetCategory; // null se for ganho
  
  // Novos campos para periodicidade
  final TransactionFrequency frequency;
  final int? dayOfWeek; // 0=Dom, 1=Seg, ..., 6=Sáb (apenas para semanais)
  final int? dayOfMonth; // 1-31 (apenas para mensais)

  // Campo para pessoa (string, opcional, padrão "geral")
  final String? person;

  Transaction({
    required this.id,
    required this.type,
    required this.date,
    this.description,
    required this.amount,
    required this.category,
    this.isSalary = false,
    this.salaryAllocation,
    this.expenseBudgetCategory,
    this.frequency = TransactionFrequency.unique,
    this.dayOfWeek,
    this.dayOfMonth,
    this.person,
  });

  Map<String, dynamic> toJson() {
    // Garantir que a data seja salva sem timezone (apenas data, sem hora)
    // Usar UTC para evitar problemas de timezone
    final dateOnly = DateTime.utc(date.year, date.month, date.day);
    // Formatar como YYYY-MM-DD para evitar problemas de timezone
    final dateStr = '${dateOnly.year.toString().padLeft(4, '0')}-'
        '${dateOnly.month.toString().padLeft(2, '0')}-'
        '${dateOnly.day.toString().padLeft(2, '0')}';
    return {
      'id': id,
      'type': type.name,
      'date': dateStr,
      'description': description,
      'amount': amount,
      'category': category.name,
      'isSalary': isSalary,
      'salaryAllocation': salaryAllocation?.toJson(),
      'expenseBudgetCategory': expenseBudgetCategory?.name,
      'frequency': frequency.name,
      'dayOfWeek': dayOfWeek,
      'dayOfMonth': dayOfMonth,
      'person': person,
    };
  }

  factory Transaction.fromJson(Map<String, dynamic> json) {
    // Lidar com datas que podem vir como string ou objeto DateTime
    DateTime parseDate(dynamic dateValue) {
      DateTime dateTime;
      if (dateValue is String) {
        // Se a string contém 'T' e 'Z', é ISO8601 com timezone
        if (dateValue.contains('T') && dateValue.contains('Z')) {
          // Parse como UTC e depois converter para local
          dateTime = DateTime.parse(dateValue).toLocal();
        } else if (dateValue.contains('T')) {
          // ISO8601 sem timezone, assumir local
          dateTime = DateTime.parse(dateValue);
        } else {
          // Formato YYYY-MM-DD, parse direto
          final parts = dateValue.split('-');
          if (parts.length == 3) {
            dateTime = DateTime(
              int.parse(parts[0]),
              int.parse(parts[1]),
              int.parse(parts[2]),
            );
          } else {
            dateTime = DateTime.parse(dateValue);
          }
        }
      } else if (dateValue is Map) {
        // MongoDB retorna datas como objetos
        final dateStr = dateValue['\$date'] as String? ?? dateValue.toString();
        if (dateStr.contains('T') && dateStr.contains('Z')) {
          dateTime = DateTime.parse(dateStr).toLocal();
        } else {
          dateTime = DateTime.parse(dateStr);
        }
      } else {
        dateTime = dateValue as DateTime;
      }
      // Garantir que retornamos apenas a data (sem hora) para evitar problemas de timezone
      // Usar UTC para evitar problemas de timezone
      return DateTime.utc(dateTime.year, dateTime.month, dateTime.day);
    }

    return Transaction(
      id: json['id'] as String? ?? json['_id']?.toString() ?? '',
      type: TransactionType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => TransactionType.despesa,
      ),
      date: parseDate(json['date']),
      description: json['description'] as String?,
      amount: (json['amount'] as num).toDouble(),
      category: _parseCategory(json['category']),
      isSalary: json['isSalary'] as bool? ?? false,
      salaryAllocation: json['salaryAllocation'] != null
          ? SalaryAllocation.fromJson(json['salaryAllocation'] as Map<String, dynamic>)
          : null,
      expenseBudgetCategory: json['expenseBudgetCategory'] != null
          ? ExpenseBudgetCategory.values.firstWhere(
              (e) => e.name == json['expenseBudgetCategory'],
              orElse: () => ExpenseBudgetCategory.gastos,
            )
          : null,
      frequency: TransactionFrequency.values.firstWhere(
        (e) => e.name == json['frequency'],
        orElse: () => TransactionFrequency.unique,
      ),
      dayOfWeek: json['dayOfWeek'] as int?,
      dayOfMonth: json['dayOfMonth'] as int?,
      person: json['person'] as String?,
    );
  }

  static TransactionCategory _parseCategory(dynamic categoryValue) {
    if (categoryValue == null) {
      return TransactionCategory.miscelaneos;
    }
    
    final categoryString = categoryValue.toString();
    
    try {
      return TransactionCategory.values.firstWhere(
        (e) => e.name == categoryString,
        orElse: () => TransactionCategory.miscelaneos,
      );
    } catch (e) {
      // Se houver qualquer erro, retornar categoria padrão
      return TransactionCategory.miscelaneos;
    }
  }
  
  // Calcular valores alocados do salário
  SalaryValues? get salaryValues {
    if (!isSalary || salaryAllocation == null) return null;
    return SalaryValues(
      gastos: amount * (salaryAllocation!.gastosPercent / 100),
      lazer: amount * (salaryAllocation!.lazerPercent / 100),
      poupanca: amount * (salaryAllocation!.poupancaPercent / 100),
    );
  }
}

enum TransactionType {
  ganho,
  despesa,
}

enum TransactionCategory {
  compras,
  cafe,
  combustivel,
  subscricao,
  dizimo,
  carro,
  multibanco,
  saude,
  comerFora,
  miscelaneos,
  prendas,
  extras,
  snacks,
  comprasOnline,
  comprasRoupa,
  animais,
  comunicacoes,
  // Categorias para ganhos
  salario,
  alimentacao,
  outro;

  String get displayName {
    switch (this) {
      case TransactionCategory.compras:
        return 'Compras';
      case TransactionCategory.cafe:
        return 'Café';
      case TransactionCategory.combustivel:
        return 'Combustível';
      case TransactionCategory.subscricao:
        return 'Subscrição';
      case TransactionCategory.dizimo:
        return 'Dízimo';
      case TransactionCategory.carro:
        return 'Carro';
      case TransactionCategory.multibanco:
        return 'Multibanco';
      case TransactionCategory.saude:
        return 'Saúde';
      case TransactionCategory.comerFora:
        return 'Comer fora';
      case TransactionCategory.miscelaneos:
        return 'Miscelâneos';
      case TransactionCategory.prendas:
        return 'Prendas';
      case TransactionCategory.extras:
        return 'Extras';
      case TransactionCategory.snacks:
        return 'Snacks';
      case TransactionCategory.comprasOnline:
        return 'Compras Online';
      case TransactionCategory.comprasRoupa:
        return 'Compras roupa';
      case TransactionCategory.animais:
        return 'Animais';
      case TransactionCategory.comunicacoes:
        return 'Comunicações';
      case TransactionCategory.salario:
        return 'Salário';
      case TransactionCategory.alimentacao:
        return 'Alimentação';
      case TransactionCategory.outro:
        return 'Outro';
    }
  }
}

enum TransactionFrequency {
  unique,
  weekly,
  monthly;
  
  String get displayName {
    switch (this) {
      case TransactionFrequency.unique:
        return 'Única';
      case TransactionFrequency.weekly:
        return 'Semanal';
      case TransactionFrequency.monthly:
        return 'Mensal';
    }
  }
}

enum ExpenseBudgetCategory {
  gastos,
  lazer,
  poupanca;
  
  String get displayName {
    switch (this) {
      case ExpenseBudgetCategory.gastos:
        return 'Gastos';
      case ExpenseBudgetCategory.lazer:
        return 'Lazer';
      case ExpenseBudgetCategory.poupanca:
        return 'Poupança';
    }
  }
}

class SalaryAllocation {
  final double gastosPercent;
  final double lazerPercent;
  final double poupancaPercent;

  SalaryAllocation({
    required this.gastosPercent,
    required this.lazerPercent,
    required this.poupancaPercent,
  }) : assert((gastosPercent + lazerPercent + poupancaPercent).round() == 100,
         'As percentagens devem somar 100%');

  Map<String, dynamic> toJson() {
    return {
      'gastosPercent': gastosPercent,
      'lazerPercent': lazerPercent,
      'poupancaPercent': poupancaPercent,
    };
  }

  factory SalaryAllocation.fromJson(Map<String, dynamic> json) {
    return SalaryAllocation(
      gastosPercent: (json['gastosPercent'] as num).toDouble(),
      lazerPercent: (json['lazerPercent'] as num).toDouble(),
      poupancaPercent: (json['poupancaPercent'] as num).toDouble(),
    );
  }
}

class SalaryValues {
  final double gastos;
  final double lazer;
  final double poupanca;

  SalaryValues({
    required this.gastos,
    required this.lazer,
    required this.poupanca,
  });
}
