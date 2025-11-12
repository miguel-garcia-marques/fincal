import 'package:flutter/material.dart';
import 'dart:ui';
import 'dart:async';
import '../models/transaction.dart';
import '../models/budget_balances.dart';
import '../models/period_history.dart';
import '../models/wallet.dart';
import '../services/database.dart';
import '../services/auth_service.dart';
import '../services/user_service.dart';
import '../services/api_service.dart';
import '../services/cache_service.dart';
import '../services/wallet_service.dart';
import '../services/wallet_storage_service.dart';
import '../utils/date_utils.dart';
import '../utils/responsive_fonts.dart';
import '../widgets/calendar.dart';
import '../widgets/transaction_list.dart';
import '../widgets/loading_screen.dart';
import '../main.dart';
import 'add_transaction_screen.dart';
import 'settings_menu_screen.dart';
import '../widgets/day_details_dialog.dart';
import '../widgets/period_selector_dialog.dart';
import '../widgets/period_history_dialog.dart';
import '../widgets/period_selection_dialog.dart';
import '../widgets/balance_chart.dart';
import '../widgets/bottom_nav_bar.dart';
import '../theme/app_theme.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:convert';
import 'dart:io';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final DatabaseService _databaseService = DatabaseService();
  final AuthService _authService = AuthService();
  final UserService _userService = UserService();
  final ApiService _apiService = ApiService();
  final CacheService _cacheService = CacheService();
  final WalletService _walletService = WalletService();
  final WalletStorageService _walletStorageService = WalletStorageService();

  // Wallet ativa
  Wallet? _activeWallet;

  int _selectedYear = DateTime.now().year;
  DateTime _startDate = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _endDate =
      DateTime(DateTime.now().year, DateTime.now().month + 1, 0);

  bool _showTransactions = false;
  List<Transaction> _transactions = [];
  bool _isLoading = true;
  bool _isInitialLoading = true; // Novo estado para loading inicial
  List<PeriodHistory> _periodHistories = [];
  bool _periodSelected = false;
  final GlobalKey<CalendarWidgetState> _calendarKey =
      GlobalKey<CalendarWidgetState>();
  Future<double>? _initialBalanceFuture;
  double? _cachedInitialBalance; // Cache do saldo inicial
  String? _filterPerson;
  Timer? _cacheRefreshTimer;

  @override
  void initState() {
    super.initState();
    // Assume current year but don't set dates yet
    _selectedYear = DateTime.now().year;
    // Prompt for period selection after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _initializeApp();
      // Iniciar timer de refresh automático a cada 30 segundos
      _startCacheRefreshTimer();
    });
  }

  @override
  void dispose() {
    _cacheRefreshTimer?.cancel();
    super.dispose();
  }

  // Iniciar timer para atualizar cache a cada 5 minutos (reduzido para melhorar performance)
  void _startCacheRefreshTimer() {
    _cacheRefreshTimer?.cancel();
    _cacheRefreshTimer = Timer.periodic(
      const Duration(minutes: 5),
      (_) {
        if (mounted) {
          _refreshDataInBackground();
        } else {
          _cacheRefreshTimer?.cancel();
        }
      },
    );
  }

  // Método de inicialização otimizado com cache
  Future<void> _initializeApp() async {
    // 1. Carregar wallet ativa primeiro
    await _loadActiveWallet();

    // Se não houver wallet ativa após carregar, algo deu errado
    if (_activeWallet == null) {
      if (mounted) {
        setState(() {
          _isInitialLoading = false;
        });
      }
      return;
    }

    // 2. Carregar dados do cache primeiro (rápido)
    await _loadFromCache();

    // 3. Carregar dados do servidor em paralelo
    await Future.wait([
      _loadUserData(),
      _loadPeriodHistories(),
    ]);

    // 4. Se não tiver período selecionado do cache, selecionar
    if (!_periodSelected) {
      await _selectDateRangeOnStartup();
    } else {
      // Se já tiver período do cache, carregar transações
      await _loadTransactions(savePeriod: false, useCache: true);
    }

    // 5. Marcar loading inicial como completo
    if (mounted) {
      setState(() {
        _isInitialLoading = false;
      });
    }

    // 6. Atualizar dados em background se necessário
    _refreshDataInBackground();
  }

  Future<void> _loadActiveWallet() async {
    try {
      // Primeiro, carregar dados do usuário para obter personalWalletId
      final user = await _userService.getCurrentUser();

      // Buscar todas as wallets e criar lista mutável
      final walletsList = await _walletService.getAllWallets();
      final wallets = List<Wallet>.from(walletsList);

      // Buscar wallet pessoal - tentar usar personalWalletId primeiro
      Wallet? personalWallet;

      if (user?.personalWalletId != null) {
        final personalWalletIdStr = user!.personalWalletId!.toString().trim();
        try {
          // Tentar encontrar a wallet pelo personalWalletId (normalizar IDs para comparação)
          personalWallet = wallets.firstWhere(
            (w) => w.id.toString().trim() == personalWalletIdStr,
          );
        } catch (e) {
          // Se não encontrar pelo ID na lista, tentar buscar diretamente pela API

          try {
            personalWallet =
                await _walletService.getWallet(personalWalletIdStr);
            // Adicionar à lista se não estiver lá
            if (!wallets.any((w) =>
                w.id.toString().trim() ==
                personalWallet!.id.toString().trim())) {
              wallets.add(personalWallet);
            }
          } catch (e2) {
            // Continuar para tentar encontrar por isOwner
          }
        }
      }

      // Se não encontrou pelo personalWalletId, tentar por isOwner
      if (personalWallet == null) {
        final ownedWallets = wallets.where((w) => w.isOwner).toList();
        if (ownedWallets.isNotEmpty) {
          // Se houver múltiplas wallets pessoais, usar a primeira (mais antiga)
          // O backend agora garante que não serão criadas novas, mas pode haver duplicatas antigas
          personalWallet = ownedWallets.first;

          // Se houver múltiplas, logar para debug e remover duplicatas da lista
          if (ownedWallets.length > 1) {
            // Remover wallets pessoais duplicadas da lista, mantendo apenas a primeira
            wallets.removeWhere((w) => w.isOwner && w.id != personalWallet!.id);
          }
        } else {
          // Se não há wallet pessoal, criar uma (o backend retornará a existente se já houver)

          try {
            personalWallet = await _walletService.createWallet();
            // Adicionar à lista se não estiver lá
            if (!wallets.any((w) => w.id == personalWallet!.id)) {
              wallets.add(personalWallet);
            }
          } catch (e2) {
            if (mounted) {
              setState(() {
                _isInitialLoading = false;
              });
            }
            return;
          }
        }
      }

      // Se não houver outras wallets além da pessoal, usar a pessoal automaticamente
      if (wallets.length == 1 && wallets.first.id == personalWallet.id) {
        await _walletStorageService.setActiveWalletId(personalWallet.id);
        if (mounted) {
          setState(() {
            _activeWallet = personalWallet;
          });
        }
        return; // Não mostrar dialog, usar diretamente
      }

      // Se houver outras wallets, verificar se há uma ativa
      final activeWalletId = await _walletStorageService.getActiveWalletId();
      if (activeWalletId != null) {
        try {
          final wallet = wallets.firstWhere((w) => w.id == activeWalletId);
          if (mounted) {
            setState(() {
              _activeWallet = wallet;
            });
          }
        } catch (e) {
          // Wallet ativa não existe mais, usar a pessoal por padrão
          await _walletStorageService.setActiveWalletId(personalWallet.id);
          if (mounted) {
            setState(() {
              _activeWallet = personalWallet;
            });
          }
        }
      } else {
        // Se não houver wallet ativa, usar a pessoal por padrão
        await _walletStorageService.setActiveWalletId(personalWallet.id);
        if (mounted) {
          setState(() {
            _activeWallet = personalWallet;
          });
        }
      }
    } catch (e) {
      // Em caso de erro, não criar wallet aqui - deve ser criada no backend
      if (mounted) {
        setState(() {
          _isInitialLoading = false;
        });
      }
    }
  }

  // Carregar dados do cache
  Future<void> _loadFromCache() async {
    try {
      if (!mounted) return;

      // Carregar período atual do cache
      final cachedPeriod = await _cacheService.getCachedCurrentPeriod();
      if (cachedPeriod != null && mounted) {
        setState(() {
          _startDate = cachedPeriod['startDate'] as DateTime;
          _endDate = cachedPeriod['endDate'] as DateTime;
          _selectedYear = cachedPeriod['selectedYear'] as int;
          _periodSelected = true;
        });
      }

      if (!mounted) return;

      // Carregar períodos do cache apenas se a wallet ativa já estiver definida
      // e se for a wallet do usuário (para evitar mostrar períodos errados)
      // Se a wallet não for do usuário, não usar cache de períodos
      if (_activeWallet != null && _activeWallet!.isOwner) {
        final cachedPeriods = await _cacheService.getCachedPeriodHistories();
        if (cachedPeriods != null && cachedPeriods.isNotEmpty && mounted) {
          setState(() {
            _periodHistories = cachedPeriods;
          });
        }
      }
      // Se não for wallet do usuário, não usar cache de períodos
      // Os períodos serão carregados do servidor em _loadPeriodHistories()

      if (!mounted) return;

      // Carregar transações do cache se tiver período selecionado
      if (_periodSelected) {
        final cachedTransactions = await _cacheService.getCachedTransactions();
        if (cachedTransactions != null &&
            cachedTransactions.isNotEmpty &&
            mounted) {
          setState(() {
            _transactions = cachedTransactions;
            _isLoading = false;
          });
          // Inicializar o saldo inicial para o gráfico poder ser exibido
          _initialBalanceFuture = _calculateInitialBalance();
        }
      }
    } catch (e) {}
  }

  // Atualizar dados em background (apenas se cache expirou)
  Future<void> _refreshDataInBackground() async {
    try {
      if (!mounted) return;

      // Verificar se o cache é válido
      final isCacheValid = await _cacheService.isCacheValid();

      if (!mounted) return;

      // Só atualizar se cache expirou
      if (!isCacheValid && _activeWallet != null) {
        // Atualizar períodos apenas se necessário
        if (_periodHistories.isEmpty) {
          // Se a wallet ativa não é do usuário logado, carregar períodos do dono da wallet
          final ownerId =
              !_activeWallet!.isOwner ? _activeWallet!.ownerId : null;
          final periods =
              await _apiService.getAllPeriodHistories(ownerId: ownerId);
          if (mounted) {
            setState(() {
              _periodHistories = periods;
            });
            await _cacheService.cachePeriodHistories(periods);
          }
        }

        if (!mounted) return;

        // Atualizar transações apenas se tiver período selecionado
        if (_periodSelected) {
          final transactions = await _databaseService.getTransactionsInRange(
            _startDate,
            _endDate,
            walletId: _activeWallet!.id,
          );
          if (mounted) {
            setState(() {
              _transactions = transactions;
            });
            await _cacheService.cacheTransactions(transactions);
          }
        }
      }
    } catch (e) {}
  }

  Future<void> _loadUserData() async {
    try {
      await _userService.getCurrentUser();
    } catch (e) {}
  }

  Future<void> _loadPeriodHistories() async {
    try {
      // Se a wallet ativa não é do usuário logado, carregar períodos do dono da wallet
      final ownerId = _activeWallet != null && !_activeWallet!.isOwner
          ? _activeWallet!.ownerId
          : null;

      final periods = await _apiService.getAllPeriodHistories(ownerId: ownerId);
      if (mounted) {
        setState(() {
          _periodHistories = periods;
        });
        // Salvar no cache
        await _cacheService.cachePeriodHistories(periods);
      }
    } catch (e) {}
  }

  Future<void> _selectDateRangeOnStartup() async {
    // Set default to current month
    final now = DateTime.now();
    _startDate = DateTime(now.year, now.month, 1);
    _endDate = DateTime(now.year, now.month + 1, 0);

    // Show period selection dialog if user has past periods
    if (_periodHistories.isNotEmpty) {
      final result = await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => PeriodSelectionDialog(
          pastPeriods: _periodHistories,
          currentYear: _selectedYear,
        ),
      );

      if (result != null && mounted) {
        if (result['type'] == 'existing') {
          final period = result['period'] as PeriodHistory;
          setState(() {
            _startDate = period.startDate;
            _endDate = period.endDate;
            _selectedYear = period.startDate.year;
            _periodSelected = true;
          });
          await _loadTransactions(savePeriod: false, useCache: false);
        } else if (result['type'] == 'new') {
          setState(() {
            _selectedYear = result['year'];
            _startDate = result['startDate'];
            _endDate = result['endDate'];
            _periodSelected = true;
          });
          await _loadTransactions(
              savePeriod: true,
              periodName: result['name'] as String? ?? '',
              useCache: false);
        }
      }
    } else {
      // No past periods, show period selector
      await _selectPeriod();
    }
  }

  // Função dedicada para reload completo (usada pelo botão de reload e após import)
  Future<void> _reloadAllData() async {
    if (!mounted || _activeWallet == null) return;

    // Invalidar cache para forçar reload do servidor
    await _cacheService.invalidateCache();

    // Recarregar transações
    await _loadTransactions(savePeriod: false, useCache: false);

    // Forçar atualização do calendário
    if (mounted && _calendarKey.currentState != null) {
      _calendarKey.currentState?.refreshCalendar();
    }
  }

  Future<void> _loadTransactions({
    bool savePeriod = false,
    String periodName = '',
    bool useCache = false,
  }) async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    List<Transaction> transactions = [];

    // Tentar carregar do cache primeiro se solicitado
    if (useCache) {
      final cachedTransactions = await _cacheService.getCachedTransactions();
      if (cachedTransactions != null && cachedTransactions.isNotEmpty) {
        transactions = cachedTransactions;
        if (mounted) {
          setState(() {
            _transactions = transactions;
            _isLoading = false;
          });
          // Continuar em background para atualizar
          _refreshTransactionsInBackground();
        }
        return;
      }
    }

    // Carregar do servidor
    if (_activeWallet == null) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
      return;
    }

    transactions = await _databaseService.getTransactionsInRange(
      _startDate,
      _endDate,
      walletId: _activeWallet!.id,
    );

    // Save period history with transaction IDs only if requested
    if (savePeriod) {
      final transactionIds = transactions.map((t) => t.id).toList();
      try {
        final periodHistory = PeriodHistory(
          id: '', // Will be generated by backend
          startDate: _startDate,
          endDate: _endDate,
          transactionIds: transactionIds,
          name: periodName,
        );
        // Se a wallet ativa não é do usuário logado, criar período para o dono da wallet
        final ownerId = _activeWallet != null && !_activeWallet!.isOwner
            ? _activeWallet!.ownerId
            : null;
        await _apiService.savePeriodHistory(periodHistory, ownerId: ownerId);
        await _loadPeriodHistories();
      } catch (e) {}
    }

    // Salvar no cache
    await _cacheService.cacheTransactions(transactions);
    await _cacheService.cacheCurrentPeriod(
      startDate: _startDate,
      endDate: _endDate,
      selectedYear: _selectedYear,
    );

    // Recriar a Future do saldo inicial quando o período mudar
    // Invalidar cache do saldo inicial quando período muda
    _cachedInitialBalance = null;
    _initialBalanceFuture = _calculateInitialBalance();

    if (mounted) {
      setState(() {
        _transactions = transactions;
        _isLoading = false;
      });
      // Forçar atualização do calendário após carregar transações
      if (_calendarKey.currentState != null) {
        _calendarKey.currentState?.refreshCalendar();
      }
    }
  }

  // Atualizar transações em background
  Future<void> _refreshTransactionsInBackground() async {
    try {
      if (_activeWallet == null) return;

      final transactions = await _databaseService.getTransactionsInRange(
        _startDate,
        _endDate,
        walletId: _activeWallet!.id,
      );
      if (mounted) {
        setState(() {
          _transactions = transactions;
        });
        await _cacheService.cacheTransactions(transactions);
        // Forçar atualização do calendário após atualizar transações
        if (_calendarKey.currentState != null) {
          _calendarKey.currentState?.refreshCalendar();
        }
      }
    } catch (e) {}
  }

  Future<void> _selectPeriod() async {
    final result = await showDialog(
      context: context,
      builder: (context) => PeriodSelectorDialog(
        selectedYear: _selectedYear,
        startDate: _startDate,
        endDate: _endDate,
      ),
    );

    if (result != null && mounted) {
      setState(() {
        _selectedYear = result['year'];
        _startDate = result['startDate'];
        _endDate = result['endDate'];
        _periodSelected = true;
      });
      await _loadTransactions(
          savePeriod: true, periodName: result['name'] as String? ?? '');
    }
  }

  Future<void> _showPeriodHistory() async {
    if (_activeWallet == null) return;

    await showDialog(
      context: context,
      builder: (context) => PeriodHistoryDialog(
        periods: _periodHistories,
        walletId: _activeWallet!.id,
        onPeriodSelected: (period) async {
          setState(() {
            _startDate = period.startDate;
            _endDate = period.endDate;
            _selectedYear = period.startDate.year;
          });
          await _loadTransactions(savePeriod: false, useCache: false);
        },
        onPeriodDeleted: (id) async {
          try {
            await _apiService.deletePeriodHistory(id);
            await _loadPeriodHistories();
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Período excluído com sucesso')),
              );
            }
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Erro ao excluir período: $e')),
              );
            }
          }
        },
        onPeriodUpdated: (updatedPeriod) async {
          try {
            await _loadPeriodHistories();
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text('Nome do período atualizado com sucesso')),
              );
            }
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Erro ao atualizar período: $e')),
              );
            }
          }
        },
      ),
    );
  }

  Future<void> _showAddTransactionDialog() async {
    if (_activeWallet == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Por favor, selecione uma carteira primeiro')),
      );
      return;
    }

    final userId = _authService.currentUser?.id;
    if (userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Usuário não autenticado')),
      );
      return;
    }

    // Verificar permissão antes de abrir o diálogo
    if (_activeWallet!.permission == 'read') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('Você só tem permissão para visualizar este calendário'),
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    final result = await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: true,
      enableDrag: true,
      builder: (context) => AddTransactionScreen(
        walletId: _activeWallet!.id,
        userId: userId,
      ),
    );

    if (result == true) {
      await _loadTransactions(savePeriod: false, useCache: false);
    }
  }

  List<String> get _availablePersons {
    final persons = <String>{'geral'};
    for (var tx in _transactions) {
      if (tx.person != null && tx.person!.isNotEmpty) {
        persons.add(tx.person!);
      }
    }
    return persons.toList()..sort();
  }

  Widget _buildPersonFilter() {
    if (_availablePersons.length <= 1) {
      return const SizedBox.shrink();
    }

    return DropdownButton<String>(
      value: _filterPerson,
      hint: const Text('Todas'),
      isDense: true,
      items: [
        const DropdownMenuItem<String>(
          value: null,
          child: Text('Todas'),
        ),
        ..._availablePersons.map((person) => DropdownMenuItem<String>(
              value: person,
              child: Text(person == 'geral' ? 'Geral' : person),
            )),
      ],
      onChanged: (value) {
        setState(() {
          _filterPerson = value;
        });
      },
    );
  }

  Future<void> _showTransactionsAsPopup() async {
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth >= 1400;

    if (isDesktop) {
      // Desktop: usar dialog
      await showDialog(
        context: context,
        builder: (context) => Dialog(
          child: Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.9,
              maxHeight: MediaQuery.of(context).size.height * 0.8,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Cabeçalho do diálogo
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: const BoxDecoration(
                    color: AppTheme.white,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(24),
                      topRight: Radius.circular(24),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Transações',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                // Lista de transações
                Expanded(
                  child: _activeWallet != null &&
                          _authService.currentUser?.id != null
                      ? TransactionListWidget(
                          transactions: _transactions,
                          onTransactionUpdated: () async {
                            await _loadTransactions(
                                savePeriod: false, useCache: false);
                            if (mounted) {
                              Navigator.of(context).pop();
                              _showTransactionsAsPopup();
                            }
                          },
                          walletId: _activeWallet!.id,
                          userId: _authService.currentUser!.id,
                          walletPermission: _activeWallet!.permission,
                        )
                      : const Center(child: CircularProgressIndicator()),
                ),
              ],
            ),
          ),
        ),
      );
    } else {
      // Mobile: usar fullscreen
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => Scaffold(
            backgroundColor: AppTheme.white,
            appBar: AppBar(
              backgroundColor: AppTheme.white,
              elevation: 0,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back, color: AppTheme.black),
                onPressed: () => Navigator.of(context).pop(),
              ),
              title: Text(
                'Transações',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppTheme.black,
                    ),
              ),
              centerTitle: true,
            ),
            body: _activeWallet != null && _authService.currentUser?.id != null
                ? TransactionListWidget(
                    transactions: _transactions,
                    onTransactionUpdated: () async {
                      await _loadTransactions(
                          savePeriod: false, useCache: false);
                      if (mounted) {
                        Navigator.of(context).pop();
                        _showTransactionsAsPopup();
                      }
                    },
                    walletId: _activeWallet!.id,
                    userId: _authService.currentUser!.id,
                    walletPermission: _activeWallet!.permission,
                  )
                : const Center(child: CircularProgressIndicator()),
          ),
          fullscreenDialog: true,
        ),
      );
    }
  }

  Future<void> _showBalancePopup() async {
    final summary = _calculateSummary();
    final balance = summary['gains']! - summary['expenses']!;

    await showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.9,
            maxHeight: MediaQuery.of(context).size.height * 0.6,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Cabeçalho do diálogo
              Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                  color: AppTheme.white,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(24),
                    topRight: Radius.circular(24),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Resumo Financeiro',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              // Conteúdo: Gráfico, Saldo, Ganhos e Despesas
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      // Gráfico de progressão
                      FutureBuilder<double>(
                        future: _initialBalanceFuture ?? Future.value(0.0),
                        builder: (context, snapshot) {
                          final initialBalance =
                              _cachedInitialBalance ?? snapshot.data ?? 0.0;

                          return BalanceChart(
                            startDate: _startDate,
                            endDate: _endDate,
                            dailyBalances: _calculateDailyBalancesForChart(),
                            initialBalance: initialBalance,
                          );
                        },
                      ),
                      const SizedBox(height: 16),
                      // Card de Saldo
                      _SummaryCard(
                        title: 'Saldo',
                        value: formatCurrency(balance),
                        color: AppTheme.darkGray,
                        isFullWidth: true,
                        isTall: true,
                      ),
                      const SizedBox(height: 16),
                      // Ganhos e Despesas lado a lado
                      Row(
                        children: [
                          Expanded(
                            child: _SummaryCard(
                              title: 'Ganhos',
                              value: formatCurrency(summary['gains']!),
                              color: AppTheme.incomeGreen,
                              count: _transactions
                                  .where((t) => t.type == TransactionType.ganho)
                                  .length,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _SummaryCard(
                              title: 'Despesas',
                              value: formatCurrency(summary['expenses']!),
                              color: AppTheme.expenseRed,
                              count: _transactions
                                  .where(
                                      (t) => t.type == TransactionType.despesa)
                                  .length,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showDayDetails(DateTime date) async {
    // Usar transações já carregadas em memória em vez de fazer nova requisição
    // Isso torna a abertura do diálogo instantânea
    final checkDate = DateTime(date.year, date.month, date.day);
    final startDateNormalized =
        DateTime(_startDate.year, _startDate.month, _startDate.day);

    // Filtrar transações até a data clicada (incluindo a data)
    final allTransactions = _transactions.where((t) {
      final transactionDate = DateTime(t.date.year, t.date.month, t.date.day);
      return (transactionDate.isAfter(startDateNormalized) ||
              transactionDate.isAtSameMomentAs(startDateNormalized)) &&
          (transactionDate.isBefore(checkDate) ||
              transactionDate.isAtSameMomentAs(checkDate));
    }).toList();

    double balance = 0.0;
    double gastos = 0.0;
    double lazer = 0.0;
    double poupanca = 0.0;

    for (var transaction in allTransactions) {
      if (transaction.type == TransactionType.ganho) {
        if (transaction.isSalary && transaction.salaryValues != null) {
          // Para salários, adicionar o valor total mas subtrair a poupança (que é despesa)
          final poupancaAmount = transaction.salaryValues!.poupanca;
          balance += transaction.amount - poupancaAmount;

          // Calcular valores do salário
          final values = transaction.salaryValues;
          gastos += values!.gastos;
          lazer += values.lazer;
          // Poupança é considerada despesa, então subtrair em vez de adicionar
          poupanca -= values.poupanca;
        } else if (transaction.category == TransactionCategory.alimentacao) {
          // Ganhos de alimentação entram como valor positivo em "gastos"
          balance += transaction.amount;
          gastos += transaction.amount;
        } else {
          balance += transaction.amount;
        }
      } else {
        balance -= transaction.amount;

        // Deduzir da categoria correspondente
        switch (transaction.expenseBudgetCategory) {
          case ExpenseBudgetCategory.gastos:
            gastos -= transaction.amount;
            break;
          case ExpenseBudgetCategory.lazer:
            lazer -= transaction.amount;
            break;
          case ExpenseBudgetCategory.poupanca:
            poupanca -= transaction.amount;
            break;
          case null:
            break;
        }
      }
    }

    final dayTransactions = _transactions.where((t) {
      final transactionDate = DateTime(t.date.year, t.date.month, t.date.day);
      return isSameDay(transactionDate, date);
    }).toList();

    final budgetBalances = (gastos != 0 || lazer != 0 || poupanca != 0)
        ? BudgetBalances(gastos: gastos, lazer: lazer, poupanca: poupanca)
        : null;

    if (mounted) {
      showDialog(
        context: context,
        builder: (context) => DayDetailsDialog(
          date: date,
          transactions: dayTransactions,
          availableBalance: balance,
          budgetBalances: budgetBalances,
          allPeriodTransactions: _transactions,
          periodStartDate: _startDate,
          periodEndDate: _endDate,
        ),
      );
    }
  }

  Map<String, double> _calculateSummary() {
    double totalGains = 0.0;
    double totalExpenses = 0.0;

    for (var transaction in _transactions) {
      if (transaction.type == TransactionType.ganho) {
        if (transaction.isSalary && transaction.salaryValues != null) {
          // Para salários, adicionar o valor total mas considerar a poupança como despesa
          final poupancaAmount = transaction.salaryValues!.poupanca;
          totalGains += transaction.amount;
          totalExpenses += poupancaAmount;
        } else {
          totalGains += transaction.amount;
        }
      } else {
        totalExpenses += transaction.amount;
      }
    }

    return {
      'gains': totalGains,
      'expenses': totalExpenses,
    };
  }

  String _formatPeriodDates(DateTime startDate, DateTime endDate) {
    final startDay = startDate.day.toString().padLeft(2, '0');
    final startMonth = startDate.month.toString().padLeft(2, '0');
    final endDay = endDate.day.toString().padLeft(2, '0');
    final endMonth = endDate.month.toString().padLeft(2, '0');

    return '$startDay/$startMonth - $endDay/$endMonth';
  }

  Future<double> _calculateInitialBalance() async {
    // Se já temos o saldo em cache e as transações não mudaram, retornar cache
    if (_cachedInitialBalance != null && _transactions.isNotEmpty) {
      // Verificar se o período ainda é o mesmo
      final cachedPeriod = await _cacheService.getCachedCurrentPeriod();
      if (cachedPeriod != null &&
          cachedPeriod['startDate'] == _startDate &&
          cachedPeriod['endDate'] == _endDate) {
        return _cachedInitialBalance!;
      }
    }

    // Calcular saldo de todas as transações antes do período começar
    try {
      final beforePeriod = _startDate.subtract(const Duration(days: 1));

      // Tentar usar transações já carregadas se possível
      double balance = 0.0;

      // Se temos transações carregadas, podemos calcular parcialmente
      // Mas ainda precisamos das transações antes do período
      if (_activeWallet == null) return 0.0;

      final allTransactions = await _databaseService.getTransactionsInRange(
        DateTime(1900, 1, 1), // Data muito antiga para pegar todas
        beforePeriod,
        walletId: _activeWallet!.id,
      );

      for (var transaction in allTransactions) {
        if (transaction.type == TransactionType.ganho) {
          if (transaction.isSalary && transaction.salaryValues != null) {
            // Para salários, adicionar o valor total mas subtrair a poupança (que é despesa)
            final poupancaAmount = transaction.salaryValues!.poupanca;
            balance += transaction.amount - poupancaAmount;
          } else {
            balance += transaction.amount;
          }
        } else {
          balance -= transaction.amount;
        }
      }

      // Cachear o resultado
      _cachedInitialBalance = balance;
      return balance;
    } catch (e) {
      return 0.0;
    }
  }

  Map<DateTime, double> _calculateDailyBalancesForChart() {
    final days = getDaysInRange(_startDate, _endDate);
    final Map<DateTime, double> dailyBalances = {};

    if (_transactions.isEmpty) {
      for (var day in days) {
        final dayOnly = DateTime(day.year, day.month, day.day);
        dailyBalances[dayOnly] = 0.0;
      }
      return dailyBalances;
    }

    // Ordenar transações por data
    final sortedTransactions = List<Transaction>.from(_transactions)
      ..sort((a, b) => a.date.compareTo(b.date));

    int transactionIndex = 0;

    for (var day in days) {
      final currentDay = DateTime.utc(day.year, day.month, day.day);
      double dayBalance = 0.0;

      // Processar todas as transações deste dia
      while (transactionIndex < sortedTransactions.length) {
        final transaction = sortedTransactions[transactionIndex];
        final transactionDate = DateTime.utc(
          transaction.date.year,
          transaction.date.month,
          transaction.date.day,
        );

        if (transactionDate.isAfter(currentDay)) {
          break;
        }

        if (transactionDate.year == currentDay.year &&
            transactionDate.month == currentDay.month &&
            transactionDate.day == currentDay.day) {
          if (transaction.type == TransactionType.ganho) {
            if (transaction.isSalary && transaction.salaryValues != null) {
              // Para salários, adicionar o valor total mas subtrair a poupança (que é despesa)
              final poupancaAmount = transaction.salaryValues!.poupanca;
              dayBalance += transaction.amount - poupancaAmount;
            } else {
              dayBalance += transaction.amount;
            }
          } else {
            dayBalance -= transaction.amount;
          }
          transactionIndex++;
        } else {
          break;
        }
      }

      final dayOnly = DateTime(day.year, day.month, day.day);
      dailyBalances[dayOnly] = dayBalance;
    }

    return dailyBalances;
  }

  @override
  Widget build(BuildContext context) {
    // Mostrar tela de loading durante inicialização
    if (_isInitialLoading) {
      return const LoadingScreen(
        message: 'Carregando seus dados financeiros...',
      );
    }

    final summary = _calculateSummary();
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth >= 1400;

    return Scaffold(
      backgroundColor: AppTheme.white,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                // Cabeçalho
                Container(
                  padding: EdgeInsets.all(isDesktop ? 24 : 12),
                  margin: EdgeInsets.only(bottom: isDesktop ? 20 : 14),
                  decoration: const BoxDecoration(
                    color: AppTheme.white,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'FinCal',
                        style:
                            Theme.of(context).textTheme.displayMedium?.copyWith(
                                  fontSize: isDesktop
                                      ? ResponsiveFonts.getFontSize(context, 32)
                                      : null,
                                ),
                      ),
                      Row(
                        children: [
                          // Filtro por pessoa
                          _buildPersonFilter(),
                          const SizedBox(width: 8),
                          // Botão de reload
                          IconButton(
                            onPressed: () async {
                              await _reloadAllData();
                            },
                            icon: const Icon(
                              Icons.refresh,
                              color: AppTheme.black,
                            ),
                            tooltip: 'Recarregar transações e calendário',
                            style: IconButton.styleFrom(
                              backgroundColor: Colors.transparent,
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Botão do menu (Definições e Sair)
                          PopupMenuButton<String>(
                            icon: const Icon(Icons.menu, color: AppTheme.black),
                            onSelected: (value) async {
                              if (value == 'settings') {
                                if (_activeWallet != null) {
                                  final result =
                                      await Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (context) => SettingsMenuScreen(
                                        currentWallet: _activeWallet!,
                                      ),
                                    ),
                                  );
                                  // Se a wallet foi alterada, recarregar
                                  if (result == true && mounted) {
                                    await _loadActiveWallet();
                                    // Recarregar períodos do dono da nova wallet
                                    await _loadPeriodHistories();
                                    await _loadTransactions(useCache: false);
                                  }
                                }
                              } else if (value == 'logout') {
                                // Mostrar diálogo de confirmação
                                final shouldLogout = await showDialog<bool>(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: const Text('Confirmar Logout'),
                                    content: const Text(
                                        'Tem certeza que deseja sair?'),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.of(context).pop(false),
                                        child: const Text('Cancelar'),
                                      ),
                                      ElevatedButton(
                                        onPressed: () =>
                                            Navigator.of(context).pop(true),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: AppTheme.expenseRed,
                                        ),
                                        child: const Text('Sair'),
                                      ),
                                    ],
                                  ),
                                );

                                if (shouldLogout == true && mounted) {
                                  try {
                                    // Fazer logout
                                    await _authService.signOut();

                                    // Aguardar um pouco para garantir que o logout foi processado
                                    await Future.delayed(
                                        const Duration(milliseconds: 100));

                                    if (mounted) {
                                      // Sempre navegar para AuthWrapper, independente do estado
                                      // O AuthWrapper vai verificar a autenticação e mostrar login se necessário
                                      Navigator.of(context).pushAndRemoveUntil(
                                        MaterialPageRoute(
                                          builder: (context) =>
                                              const AuthWrapper(),
                                        ),
                                        (route) =>
                                            false, // Remove todas as rotas anteriores
                                      );
                                    }
                                  } catch (e) {
                                    if (mounted) {
                                      // Mesmo em caso de erro, navegar para AuthWrapper
                                      // para garantir que o usuário não fique preso
                                      Navigator.of(context).pushAndRemoveUntil(
                                        MaterialPageRoute(
                                          builder: (context) =>
                                              const AuthWrapper(),
                                        ),
                                        (route) => false,
                                      );

                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        SnackBar(
                                          content:
                                              Text('Erro ao fazer logout: $e'),
                                          backgroundColor: AppTheme.expenseRed,
                                        ),
                                      );
                                    }
                                  }
                                }
                              }
                            },
                            itemBuilder: (context) => [
                              const PopupMenuItem(
                                value: 'settings',
                                child: Row(
                                  children: [
                                    Icon(Icons.settings, color: AppTheme.black),
                                    SizedBox(width: 12),
                                    Text('Definições'),
                                  ],
                                ),
                              ),
                              const PopupMenuItem(
                                value: 'logout',
                                child: Row(
                                  children: [
                                    Icon(Icons.logout,
                                        color: AppTheme.expenseRed),
                                    SizedBox(width: 12),
                                    Text('Sair',
                                        style: TextStyle(
                                            color: AppTheme.expenseRed)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Conteúdo principal
                Expanded(
                  child: !_periodSelected
                      ? const Center(child: CircularProgressIndicator())
                      : _isLoading
                          ? const Center(child: CircularProgressIndicator())
                          : Stack(
                              children: [
                                AnimatedContainer(
                                  duration: const Duration(milliseconds: 300),
                                  curve: Curves.easeInOut,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 0, vertical: 0),
                                  child: LayoutBuilder(
                                    builder: (context, constraints) {
                                      final layoutWidth = constraints.maxWidth;
                                      final usePopupForTransactions =
                                          layoutWidth < 1300;
                                      final isDesktopLayout =
                                          layoutWidth >= 1400;

                                      if (isDesktopLayout) {
                                        // Desktop layout: sempre calendário à esquerda e lista à direita
                                        return Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            // Calendário
                                            Expanded(
                                              flex: 3,
                                              child: CalendarWidget(
                                                key: _calendarKey,
                                                startDate: _startDate,
                                                endDate: _endDate,
                                                transactions: _transactions,
                                                onDayTap: _showDayDetails,
                                                filterPerson: _filterPerson,
                                              ),
                                            ),
                                            // Lista de transações (sempre visível no desktop)
                                            const SizedBox(width: 24),
                                            Expanded(
                                              flex: 2,
                                              child: _activeWallet != null &&
                                                      _authService.currentUser
                                                              ?.id !=
                                                          null
                                                  ? TransactionListWidget(
                                                      transactions:
                                                          _transactions,
                                                      onTransactionUpdated:
                                                          () async {
                                                        await _loadTransactions(
                                                            savePeriod: false,
                                                            useCache: false);
                                                      },
                                                      walletId:
                                                          _activeWallet!.id,
                                                      userId: _authService
                                                          .currentUser!.id,
                                                      walletPermission:
                                                          _activeWallet!
                                                              .permission,
                                                    )
                                                  : const Center(
                                                      child:
                                                          CircularProgressIndicator()),
                                            ),
                                          ],
                                        );
                                      }

                                      // Mobile/Tablet layout
                                      return ConstrainedBox(
                                        constraints:
                                            const BoxConstraints(maxWidth: 650),
                                        child: Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            // Calendário e Gráfico
                                            Expanded(
                                              flex: _showTransactions &&
                                                      !usePopupForTransactions
                                                  ? 2
                                                  : 1,
                                              child: Column(
                                                mainAxisSize: MainAxisSize.max,
                                                children: [
                                                  // Calendário
                                                  Expanded(
                                                    child: CalendarWidget(
                                                      key: _calendarKey,
                                                      startDate: _startDate,
                                                      endDate: _endDate,
                                                      transactions:
                                                          _transactions,
                                                      onDayTap: _showDayDetails,
                                                      filterPerson:
                                                          _filterPerson,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            // Lista de transações (só mostra ao lado se não for popup)
                                            if (_showTransactions &&
                                                !usePopupForTransactions) ...[
                                              const SizedBox(width: 12),
                                              Expanded(
                                                flex: 1,
                                                child: _activeWallet != null &&
                                                        _authService.currentUser
                                                                ?.id !=
                                                            null
                                                    ? TransactionListWidget(
                                                        transactions:
                                                            _transactions,
                                                        onTransactionUpdated:
                                                            () async {
                                                          await _loadTransactions(
                                                              savePeriod: false,
                                                              useCache: false);
                                                        },
                                                        walletId:
                                                            _activeWallet!.id,
                                                        userId: _authService
                                                            .currentUser!.id,
                                                        walletPermission:
                                                            _activeWallet!
                                                                .permission,
                                                      )
                                                    : const Center(
                                                        child:
                                                            CircularProgressIndicator()),
                                              ),
                                            ],
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ),
                ),

                // Resumo mensal
                LayoutBuilder(
                  builder: (context, constraints) {
                    final screenHeight = MediaQuery.of(context).size.height;
                    final shouldShowBalanceAsPopup = screenHeight < 700;

                    if (shouldShowBalanceAsPopup) {
                      // Layout em linha para ecrãs pequenos: Período e Resumo lado a lado
                      final screenWidth = MediaQuery.of(context).size.width;
                      final isDesktop = screenWidth >= 1400;
                      return Container(
                        padding: EdgeInsets.fromLTRB(
                            12, isDesktop ? 16 : 12, 12, isDesktop ? 16 : 12),
                        decoration: const BoxDecoration(
                          color: AppTheme.white,
                        ),
                        child: IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // Período - à esquerda
                              Expanded(
                                child: InkWell(
                                  onTap: _selectPeriod,
                                  borderRadius: BorderRadius.circular(12),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 10,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppTheme.white,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color:
                                            AppTheme.darkGray.withOpacity(0.2),
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        // "Período" e ano juntos na mesma linha
                                        Row(
                                          children: [
                                            Flexible(
                                              child: Text(
                                                'Período',
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .bodySmall
                                                    ?.copyWith(
                                                      color: AppTheme.darkGray,
                                                    ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            const SizedBox(width: 4),
                                            if (_startDate.year ==
                                                _endDate.year)
                                              Flexible(
                                                child: Container(
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                    horizontal: 4,
                                                    vertical: 2,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: AppTheme.darkGray
                                                        .withOpacity(0.1),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            4),
                                                  ),
                                                  child: Text(
                                                    '${_startDate.year}',
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .bodySmall
                                                        ?.copyWith(
                                                          fontSize:
                                                              ResponsiveFonts
                                                                  .getFontSize(
                                                                      context,
                                                                      9),
                                                          fontWeight:
                                                              FontWeight.w600,
                                                          color:
                                                              AppTheme.darkGray,
                                                        ),
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                ),
                                              )
                                            else
                                              Flexible(
                                                child: Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    Flexible(
                                                      child: Container(
                                                        padding:
                                                            const EdgeInsets
                                                                .symmetric(
                                                          horizontal: 4,
                                                          vertical: 2,
                                                        ),
                                                        decoration:
                                                            BoxDecoration(
                                                          color: AppTheme
                                                              .darkGray
                                                              .withOpacity(0.1),
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(4),
                                                        ),
                                                        child: Text(
                                                          '${_startDate.year}',
                                                          style:
                                                              Theme.of(context)
                                                                  .textTheme
                                                                  .bodySmall
                                                                  ?.copyWith(
                                                                    fontSize: ResponsiveFonts
                                                                        .getFontSize(
                                                                            context,
                                                                            9),
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .w600,
                                                                    color: AppTheme
                                                                        .darkGray,
                                                                  ),
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                        ),
                                                      ),
                                                    ),
                                                    Padding(
                                                      padding: const EdgeInsets
                                                          .symmetric(
                                                          horizontal: 2),
                                                      child: Text(
                                                        '-',
                                                        style: Theme.of(context)
                                                            .textTheme
                                                            .bodySmall
                                                            ?.copyWith(
                                                              fontSize:
                                                                  ResponsiveFonts
                                                                      .getFontSize(
                                                                          context,
                                                                          9),
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w600,
                                                              color: AppTheme
                                                                  .darkGray,
                                                            ),
                                                      ),
                                                    ),
                                                    Flexible(
                                                      child: Container(
                                                        padding:
                                                            const EdgeInsets
                                                                .symmetric(
                                                          horizontal: 4,
                                                          vertical: 2,
                                                        ),
                                                        decoration:
                                                            BoxDecoration(
                                                          color: AppTheme
                                                              .darkGray
                                                              .withOpacity(0.1),
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(4),
                                                        ),
                                                        child: Text(
                                                          '${_endDate.year}',
                                                          style:
                                                              Theme.of(context)
                                                                  .textTheme
                                                                  .bodySmall
                                                                  ?.copyWith(
                                                                    fontSize: ResponsiveFonts
                                                                        .getFontSize(
                                                                            context,
                                                                            9),
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .w600,
                                                                    color: AppTheme
                                                                        .darkGray,
                                                                  ),
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        // Período formatado embaixo
                                        Text(
                                          _formatPeriodDates(
                                              _startDate, _endDate),
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodyMedium
                                              ?.copyWith(
                                                fontWeight: FontWeight.w600,
                                                color: AppTheme.black,
                                              ),
                                          overflow: TextOverflow.ellipsis,
                                          maxLines: 1,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              // Botão para ver resumo financeiro - à direita
                              Expanded(
                                child: InkWell(
                                  onTap: _showBalancePopup,
                                  borderRadius: BorderRadius.circular(12),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 10,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppTheme.darkGray.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color:
                                            AppTheme.darkGray.withOpacity(0.2),
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(
                                          child: Text(
                                            'Resumo Financeiro',
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodyMedium
                                                ?.copyWith(
                                                  fontWeight: FontWeight.w600,
                                                  color: AppTheme.black,
                                                ),
                                            overflow: TextOverflow.ellipsis,
                                            maxLines: 1,
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        Icon(
                                          Icons.open_in_new,
                                          color: AppTheme.darkGray
                                              .withOpacity(0.5),
                                          size: 18,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }

                    // Mostrar normalmente quando altura >= 700
                    return Column(
                      children: [
                        // Saldo e Período
                        Container(
                          // padding: EdgeInsets.symmetric(
                          //   horizontal: isDesktop ? 24 : 12,
                          //   vertical: isDesktop ? 16 : 12,
                          // ),
                          padding: EdgeInsets.only(
                              bottom: isDesktop ? 6 : 4,
                              left: isDesktop ? 24 : 12,
                              right: isDesktop ? 24 : 12,
                              top: isDesktop ? 16 : 12),
                          decoration: const BoxDecoration(
                            color: AppTheme.white,
                          ),
                          child: IntrinsicHeight(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                // Saldo - à esquerda
                                Expanded(
                                  child: InkWell(
                                    onTap: _showBalancePopup,
                                    borderRadius: BorderRadius.circular(12),
                                    child: _SummaryCard(
                                      title: 'Saldo',
                                      value: formatCurrency(summary['gains']! -
                                          summary['expenses']!),
                                      color: AppTheme.darkGray,
                                      isFullWidth: true,
                                      isTall: true,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                // Período - à direita (agora ocupa todo o espaço)
                                Expanded(
                                  child: InkWell(
                                    onTap: _selectPeriod,
                                    borderRadius: BorderRadius.circular(12),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 10,
                                      ),
                                      decoration: BoxDecoration(
                                        color: AppTheme.white,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: AppTheme.darkGray
                                              .withOpacity(0.2),
                                        ),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          // "Período" e ano juntos na mesma linha
                                          Row(
                                            children: [
                                              Flexible(
                                                child: Text(
                                                  'Período',
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .bodySmall
                                                      ?.copyWith(
                                                        color:
                                                            AppTheme.darkGray,
                                                      ),
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                              const SizedBox(width: 4),
                                              if (_startDate.year ==
                                                  _endDate.year)
                                                Flexible(
                                                  child: Container(
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                      horizontal: 4,
                                                      vertical: 2,
                                                    ),
                                                    decoration: BoxDecoration(
                                                      color: AppTheme.darkGray
                                                          .withOpacity(0.1),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              4),
                                                    ),
                                                    child: Text(
                                                      '${_startDate.year}',
                                                      style: Theme.of(context)
                                                          .textTheme
                                                          .bodySmall
                                                          ?.copyWith(
                                                            fontSize:
                                                                ResponsiveFonts
                                                                    .getFontSize(
                                                                        context,
                                                                        9),
                                                            fontWeight:
                                                                FontWeight.w600,
                                                            color: AppTheme
                                                                .darkGray,
                                                          ),
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                )
                                              else
                                                Flexible(
                                                  child: Row(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      Flexible(
                                                        child: Container(
                                                          padding:
                                                              const EdgeInsets
                                                                  .symmetric(
                                                            horizontal: 4,
                                                            vertical: 2,
                                                          ),
                                                          decoration:
                                                              BoxDecoration(
                                                            color: AppTheme
                                                                .darkGray
                                                                .withOpacity(
                                                                    0.1),
                                                            borderRadius:
                                                                BorderRadius
                                                                    .circular(
                                                                        4),
                                                          ),
                                                          child: Text(
                                                            '${_startDate.year}',
                                                            style:
                                                                Theme.of(
                                                                        context)
                                                                    .textTheme
                                                                    .bodySmall
                                                                    ?.copyWith(
                                                                      fontSize:
                                                                          ResponsiveFonts.getFontSize(
                                                                              context,
                                                                              9),
                                                                      fontWeight:
                                                                          FontWeight
                                                                              .w600,
                                                                      color: AppTheme
                                                                          .darkGray,
                                                                    ),
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                          ),
                                                        ),
                                                      ),
                                                      Padding(
                                                        padding:
                                                            const EdgeInsets
                                                                .symmetric(
                                                                horizontal: 2),
                                                        child: Text(
                                                          '-',
                                                          style:
                                                              Theme.of(context)
                                                                  .textTheme
                                                                  .bodySmall
                                                                  ?.copyWith(
                                                                    fontSize: ResponsiveFonts
                                                                        .getFontSize(
                                                                            context,
                                                                            9),
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .w600,
                                                                    color: AppTheme
                                                                        .darkGray,
                                                                  ),
                                                        ),
                                                      ),
                                                      Flexible(
                                                        child: Container(
                                                          padding:
                                                              const EdgeInsets
                                                                  .symmetric(
                                                            horizontal: 4,
                                                            vertical: 2,
                                                          ),
                                                          decoration:
                                                              BoxDecoration(
                                                            color: AppTheme
                                                                .darkGray
                                                                .withOpacity(
                                                                    0.1),
                                                            borderRadius:
                                                                BorderRadius
                                                                    .circular(
                                                                        4),
                                                          ),
                                                          child: Text(
                                                            '${_endDate.year}',
                                                            style:
                                                                Theme.of(
                                                                        context)
                                                                    .textTheme
                                                                    .bodySmall
                                                                    ?.copyWith(
                                                                      fontSize:
                                                                          ResponsiveFonts.getFontSize(
                                                                              context,
                                                                              9),
                                                                      fontWeight:
                                                                          FontWeight
                                                                              .w600,
                                                                      color: AppTheme
                                                                          .darkGray,
                                                                    ),
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          // Período formatado embaixo
                                          Text(
                                            _formatPeriodDates(
                                                _startDate, _endDate),
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodyMedium
                                                ?.copyWith(
                                                  fontWeight: FontWeight.w600,
                                                  color: AppTheme.black,
                                                ),
                                            overflow: TextOverflow.ellipsis,
                                            maxLines: 1,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        // Ganhos e Despesas
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: isDesktop ? 24 : 12,
                            vertical: isDesktop ? 16 : 12,
                          ),
                          decoration: const BoxDecoration(
                            color: AppTheme.white,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              Expanded(
                                child: _SummaryCard(
                                  title: 'Ganhos',
                                  value: formatCurrency(summary['gains']!),
                                  color: AppTheme.incomeGreen,
                                  count: _transactions
                                      .where((t) =>
                                          t.type == TransactionType.ganho)
                                      .length,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _SummaryCard(
                                  title: 'Despesas',
                                  value: formatCurrency(summary['expenses']!),
                                  color: AppTheme.expenseRed,
                                  count: _transactions
                                      .where((t) =>
                                          t.type == TransactionType.despesa)
                                      .length,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
                // Espaço para a navbar inferior
                SizedBox(height: 90),
              ],
            ),
            // Navbar inferior
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: BottomNavBar(
                onHistoryTap: () {
                  _showPeriodHistory();
                },
                onAddTransactionTap: () {
                  _showAddTransactionDialog();
                },
                onTransactionsTap: () {
                  final screenWidth = MediaQuery.of(context).size.width;
                  if (screenWidth < 1300) {
                    _showTransactionsAsPopup();
                  } else {
                    setState(() {
                      _showTransactions = !_showTransactions;
                    });
                  }
                },
                isTransactionsActive: _showTransactions,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String title;
  final String value;
  final Color color;
  final int? count;
  final bool isFullWidth;
  final bool isTall;

  const _SummaryCard({
    required this.title,
    required this.value,
    required this.color,
    this.count,
    this.isFullWidth = false,
    this.isTall = false,
  });

  @override
  Widget build(BuildContext context) {
    final hasBorder =
        !isFullWidth && (title == 'Ganhos' || title == 'Despesas');

    return Container(
      padding: EdgeInsets.all(isTall ? 12 : (hasBorder ? 12 : 8)),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: hasBorder
            ? Border.all(
                color: color.withOpacity(0.3),
                width: 1,
              )
            : null,
      ),
      child: isFullWidth
          ? Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppTheme.darkGray,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      value,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: color,
                            fontSize: isTall
                                ? ResponsiveFonts.getFontSize(context, 18)
                                : null,
                          ),
                    ),
                  ],
                ),
              ],
            )
          : Column(
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppTheme.darkGray,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: color,
                      ),
                ),
                if (count != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    '$count transações',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppTheme.darkGray,
                        ),
                  ),
                ],
              ],
            ),
    );
  }
}

class _ImportTransactionsDialog extends StatefulWidget {
  final VoidCallback onImportComplete;
  final String walletId;
  final String userId;

  const _ImportTransactionsDialog({
    required this.onImportComplete,
    required this.walletId,
    required this.userId,
  });

  @override
  State<_ImportTransactionsDialog> createState() =>
      _ImportTransactionsDialogState();
}

class _ImportTransactionsDialogState extends State<_ImportTransactionsDialog> {
  bool _isImporting = false;
  String? _errorMessage;
  String? _successMessage;

  // Verificar se uma transação do JSON é duplicada de uma transação existente
  bool _isDuplicate(Map<String, dynamic> jsonTx, Transaction existingTx) {
    // Comparar periodicidade
    String? jsonFrequency;
    int? jsonDayOfWeek;
    int? jsonDayOfMonth;

    if (jsonTx['periodicity'] == 'mensal') {
      jsonFrequency = 'monthly';
      jsonDayOfMonth = int.tryParse(jsonTx['day']?.toString() ?? '');
    } else if (jsonTx['periodicity'] == 'semanal') {
      jsonFrequency = 'weekly';
      // Converter dia da semana de string para número
      final dayStr = (jsonTx['dayofWeek'] ?? jsonTx['day'] ?? '')
          .toString()
          .toLowerCase()
          .trim();
      final dayMap = {
        'domingo': 1,
        'dom': 1,
        'segunda': 2,
        'seg': 2,
        'terça': 2,
        'terca': 2,
        'ter': 2,
        'quarta': 4,
        'qua': 4,
        'quinta': 5,
        'qui': 5,
        'sexta': 6,
        'sex': 6,
        'sábado': 0,
        'sabado': 0,
        'sab': 0,
      };
      jsonDayOfWeek = dayMap[dayStr];
    } else {
      jsonFrequency = 'unique';
    }

    // Comparar frequência
    if (existingTx.frequency.name != jsonFrequency) return false;
    if (existingTx.frequency == TransactionFrequency.weekly &&
        existingTx.dayOfWeek != jsonDayOfWeek) return false;
    if (existingTx.frequency == TransactionFrequency.monthly &&
        existingTx.dayOfMonth != jsonDayOfMonth) return false;

    // Para transações únicas, comparar data
    if (jsonFrequency == 'unique') {
      DateTime? jsonDate;
      if (jsonTx['date'] != null) {
        jsonDate = DateTime.tryParse(jsonTx['date'].toString());
      }
      if (jsonDate != null) {
        final jsonDateOnly =
            DateTime(jsonDate.year, jsonDate.month, jsonDate.day);
        final existingDateOnly = DateTime(
            existingTx.date.year, existingTx.date.month, existingTx.date.day);
        if (jsonDateOnly != existingDateOnly) return false;
      }
    }

    // Comparar tipo
    final jsonType = jsonTx['type']?.toString();
    if (existingTx.type.name != jsonType) return false;

    // Comparar valor
    final jsonAmount = (jsonTx['value'] ?? jsonTx['amount'] ?? 0).toString();
    final jsonAmountNum = double.tryParse(jsonAmount.replaceAll(',', '.')) ?? 0;
    if ((existingTx.amount - jsonAmountNum).abs() > 0.01) return false;

    // Comparar categoria
    final jsonCategory = jsonTx['category']?.toString();
    if (existingTx.category.name != jsonCategory) return false;

    // Comparar descrição (se ambas tiverem)
    final jsonDesc = jsonTx['description']?.toString() ?? '';
    final existingDesc = existingTx.description ?? '';
    if (jsonDesc.isNotEmpty &&
        existingDesc.isNotEmpty &&
        jsonDesc != existingDesc) return false;

    // Comparar pessoa
    final jsonPerson = jsonTx['person']?.toString();
    final existingPerson = existingTx.person;
    if (jsonPerson != null && jsonPerson.isNotEmpty) {
      if (existingPerson != jsonPerson) return false;
    } else if (existingPerson != null && existingPerson.isNotEmpty) {
      return false;
    }

    return true;
  }

  Future<void> _importFromFile() async {
    setState(() {
      _isImporting = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (result != null && result.files.single.size > 0) {
        String fileContent;

        // Na web, usar bytes; em outras plataformas, usar path
        if (result.files.single.bytes != null) {
          // Web: usar bytes
          fileContent = utf8.decode(result.files.single.bytes!);
        } else if (result.files.single.path != null) {
          // Outras plataformas: usar path
          final filePath = result.files.single.path!;
          fileContent = await File(filePath).readAsString();
        } else {
          throw Exception('Não foi possível ler o arquivo');
        }

        final jsonData = json.decode(fileContent) as List<dynamic>;

        final transactions =
            jsonData.map((e) => e as Map<String, dynamic>).toList();

        // Verificar duplicatas antes de importar
        final dbService = DatabaseService();
        final existingTransactions =
            await dbService.getAllTransactions(walletId: widget.walletId);

        final duplicates = <Map<String, dynamic>>[];
        final duplicateIndices = <int>[];

        for (int i = 0; i < transactions.length; i++) {
          final tx = transactions[i];
          for (var existingTx in existingTransactions) {
            if (_isDuplicate(tx, existingTx)) {
              duplicates.add({
                'index': i,
                'transaction': tx,
                'existingId': existingTx.id,
              });
              duplicateIndices.add(i);
              break;
            }
          }
        }

        // Se houver duplicatas, mostrar diálogo com lista para seleção individual
        if (duplicates.isNotEmpty) {
          final selectedDuplicates = await showDialog<Set<int>>(
            context: context,
            builder: (context) => _DuplicateSelectionDialog(
              duplicates: duplicates,
              existingTransactions: existingTransactions,
            ),
          );

          if (selectedDuplicates == null) {
            // Usuário cancelou
            setState(() {
              _isImporting = false;
            });
            return;
          }

          // Processar apenas as duplicatas selecionadas
          if (selectedDuplicates.isNotEmpty) {
            // Sobrescrever: atualizar apenas as transações selecionadas
            final apiService = ApiService();
            for (var dup in duplicates) {
              final index = dup['index'] as int;
              if (!selectedDuplicates.contains(index)) {
                continue; // Pular se não foi selecionada
              }
              final tx = dup['transaction'] as Map<String, dynamic>;
              final existingId = dup['existingId'] as String;

              // Converter para Transaction e atualizar
              try {
                // Converter o JSON para Transaction (simplificado - usar a mesma lógica do backend)
                final amount = double.tryParse(
                        (tx['value'] ?? tx['amount'] ?? 0)
                            .toString()
                            .replaceAll(',', '.')) ??
                    0;
                DateTime? date;
                if (tx['date'] != null) {
                  date = DateTime.tryParse(tx['date'].toString());
                }
                date ??= DateTime.now();
                date = DateTime(date.year, date.month, date.day);

                String? frequency;
                int? dayOfWeek;
                int? dayOfMonth;
                if (tx['periodicity'] == 'mensal') {
                  frequency = 'monthly';
                  dayOfMonth = int.tryParse(tx['day']?.toString() ?? '');
                } else if (tx['periodicity'] == 'semanal') {
                  frequency = 'weekly';
                  final dayStr = (tx['dayofWeek'] ?? tx['day'] ?? '')
                      .toString()
                      .toLowerCase()
                      .trim();
                  final dayMap = {
                    'domingo': 1,
                    'dom': 1,
                    'segunda': 2,
                    'seg': 2,
                    'terça': 2,
                    'terca': 2,
                    'ter': 2,
                    'quarta': 4,
                    'qua': 4,
                    'quinta': 5,
                    'qui': 5,
                    'sexta': 6,
                    'sex': 6,
                    'sábado': 0,
                    'sabado': 0,
                    'sab': 0,
                  };
                  dayOfWeek = dayMap[dayStr];
                } else {
                  frequency = 'unique';
                }

                // Criar transação atualizada
                final updatedTx = Transaction(
                  id: existingId,
                  type: tx['type'] == 'ganho'
                      ? TransactionType.ganho
                      : TransactionType.despesa,
                  date: date,
                  description: tx['description']?.toString(),
                  amount: amount,
                  category: TransactionCategory.values.firstWhere(
                    (c) => c.name == tx['category']?.toString(),
                    orElse: () => TransactionCategory.miscelaneos,
                  ),
                  isSalary: tx['salary'] == true,
                  salaryAllocation: tx['salaryAllocation'] != null
                      ? SalaryAllocation(
                          gastosPercent: (tx['salaryAllocation']['gastos'] ??
                                  tx['salaryAllocation']['gastosPercent'] ??
                                  0)
                              .toDouble(),
                          lazerPercent: (tx['salaryAllocation']['lazer'] ??
                                  tx['salaryAllocation']['lazerPercent'] ??
                                  0)
                              .toDouble(),
                          poupancaPercent: (tx['salaryAllocation']
                                      ['poupanca'] ??
                                  tx['salaryAllocation']['poupancaPercent'] ??
                                  0)
                              .toDouble(),
                        )
                      : null,
                  expenseBudgetCategory: tx['budgetCategory'] != null
                      ? ExpenseBudgetCategory.values.firstWhere(
                          (c) => c.name == tx['budgetCategory']?.toString(),
                          orElse: () => ExpenseBudgetCategory.gastos,
                        )
                      : null,
                  frequency: frequency == 'monthly'
                      ? TransactionFrequency.monthly
                      : (frequency == 'weekly'
                          ? TransactionFrequency.weekly
                          : TransactionFrequency.unique),
                  dayOfWeek: dayOfWeek,
                  dayOfMonth: dayOfMonth,
                  person: tx['person']?.toString(),
                  walletId: widget.walletId,
                  createdBy: widget.userId,
                );

                await apiService.updateTransaction(updatedTx,
                    walletId: widget.walletId);
              } catch (e) {}
            }

            // Remover todas as duplicatas (selecionadas e não selecionadas) da lista de importação
            final transactionsToImport = <Map<String, dynamic>>[];
            for (int i = 0; i < transactions.length; i++) {
              if (!duplicateIndices.contains(i)) {
                transactionsToImport.add(transactions[i]);
              }
            }

            final overwrittenCount = selectedDuplicates.length;
            final ignoredCount = duplicates.length - overwrittenCount;

            if (transactionsToImport.isNotEmpty) {
              final apiService = ApiService();
              final importResult = await apiService.importBulkTransactions(
                transactionsToImport,
                walletId: widget.walletId,
              );

              if (mounted) {
                setState(() {
                  _isImporting = false;
                  String message = '';
                  if (overwrittenCount > 0) {
                    message = '$overwrittenCount transação(ões) atualizada(s)';
                  }
                  if (importResult['imported'] != null &&
                      (importResult['imported'] as int) > 0) {
                    if (message.isNotEmpty) message += ' e ';
                    message +=
                        '${importResult['imported']} nova(s) importada(s)';
                  }
                  if (ignoredCount > 0) {
                    if (message.isNotEmpty) message += ' (';
                    message += '$ignoredCount duplicata(s) ignorada(s)';
                    if (message.contains('(')) message += ')';
                  }
                  _successMessage =
                      message.isNotEmpty ? message : 'Importação concluída';
                });
              }
            } else {
              if (mounted) {
                setState(() {
                  _isImporting = false;
                  String message = '';
                  if (overwrittenCount > 0) {
                    message = '$overwrittenCount transação(ões) atualizada(s)';
                  }
                  if (ignoredCount > 0) {
                    if (message.isNotEmpty) message += ', ';
                    message += '$ignoredCount duplicata(s) ignorada(s)';
                  }
                  _successMessage = message.isNotEmpty
                      ? message
                      : 'Nenhuma transação nova para importar';
                });
              }
            }
          } else {
            // Nenhuma selecionada: remover todas as duplicatas da lista
            final transactionsToImport = <Map<String, dynamic>>[];
            for (int i = 0; i < transactions.length; i++) {
              if (!duplicateIndices.contains(i)) {
                transactionsToImport.add(transactions[i]);
              }
            }

            if (transactionsToImport.isNotEmpty) {
              final apiService = ApiService();
              final importResult = await apiService.importBulkTransactions(
                transactionsToImport,
                walletId: widget.walletId,
              );

              if (mounted) {
                setState(() {
                  _isImporting = false;
                  _successMessage =
                      '${importResult['imported'] ?? 0} transação(ões) importada(s) (${duplicates.length} duplicata(s) ignorada(s))';
                });
              }
            } else {
              if (mounted) {
                setState(() {
                  _isImporting = false;
                  _successMessage =
                      'Nenhuma transação nova para importar (todas são duplicatas)';
                });
              }
            }
          }

          // Aguardar um pouco antes de fechar
          await Future.delayed(const Duration(seconds: 2));
          if (mounted) {
            Navigator.of(context).pop();
            widget.onImportComplete();
          }
          return;
        }

        // Se não houver duplicatas, importar normalmente
        final apiService = ApiService();
        final importResult = await apiService.importBulkTransactions(
          transactions,
          walletId: widget.walletId,
        );

        if (mounted) {
          setState(() {
            _isImporting = false;
            _successMessage = importResult['message'] as String? ??
                '${importResult['imported']} transações importadas com sucesso';
          });

          // Se houver erros, mostrar diálogo de correção
          if (importResult['errors'] != null &&
              (importResult['errors'] as List).isNotEmpty) {
            final errors = importResult['errors'] as List<dynamic>;
            Navigator.of(context).pop(); // Fechar diálogo de importação

            // Mostrar diálogo de correção
            final fixed = await showDialog<List<Map<String, dynamic>>>(
              context: context,
              builder: (context) => _FixTransactionsDialog(
                errors: errors,
              ),
            );

            // Se o usuário corrigiu algumas transações, reenviar
            if (fixed != null && fixed.isNotEmpty) {
              try {
                final retryResult = await apiService.importBulkTransactions(
                  fixed,
                  walletId: widget.walletId,
                );
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(retryResult['message'] as String? ??
                          '${retryResult['imported']} transações corrigidas importadas com sucesso'),
                      backgroundColor: AppTheme.incomeGreen,
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content:
                          Text('Erro ao reimportar transações corrigidas: $e'),
                      backgroundColor: AppTheme.expenseRed,
                    ),
                  );
                }
              }
            }

            widget.onImportComplete();
          } else {
            // Aguardar um pouco antes de fechar
            await Future.delayed(const Duration(seconds: 2));
            if (mounted) {
              Navigator.of(context).pop();
              widget.onImportComplete();
            }
          }
        }
      } else {
        setState(() {
          _isImporting = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isImporting = false;
          _errorMessage = 'Erro ao importar: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Importar Transações'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_isImporting)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: CircularProgressIndicator(),
            )
          else if (_errorMessage != null)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(
                _errorMessage!,
                style: const TextStyle(color: AppTheme.expenseRed),
              ),
            )
          else if (_successMessage != null)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(
                _successMessage!,
                style: const TextStyle(color: AppTheme.incomeGreen),
              ),
            )
          else
            const Text('Selecione um arquivo JSON para importar transações.'),
          if (!_isImporting &&
              _errorMessage == null &&
              _successMessage == null) ...[
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _importFromFile,
              icon: const Icon(Icons.upload_file),
              label: const Text('Selecionar Arquivo JSON'),
            ),
          ],
        ],
      ),
      actions: [
        if (!_isImporting && _successMessage == null)
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          )
        else if (_successMessage != null || _errorMessage != null)
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Fechar'),
          ),
      ],
    );
  }
}

class _FixTransactionsDialog extends StatefulWidget {
  final List<dynamic> errors;

  const _FixTransactionsDialog({required this.errors});

  @override
  State<_FixTransactionsDialog> createState() => _FixTransactionsDialogState();
}

class _FixTransactionsDialogState extends State<_FixTransactionsDialog> {
  final Map<int, Map<String, dynamic>> _edits = {};

  @override
  void initState() {
    super.initState();
    // Inicializar com as transações originais
    for (var error in widget.errors) {
      final index = error['index'] as int;
      final tx = Map<String, dynamic>.from(error['transaction'] as Map);
      _edits[index] = tx;
    }
  }

  void _updateField(int index, String field, dynamic value) {
    setState(() {
      if (!_edits.containsKey(index)) {
        _edits[index] = Map<String, dynamic>.from(widget.errors
            .firstWhere((e) => e['index'] == index)['transaction']);
      }
      _edits[index]![field] = value;
    });
  }

  List<Map<String, dynamic>> _getFixedTransactions() {
    return _edits.values.where((tx) {
      // Validar se a transação está completa
      if (!tx.containsKey('type') || tx['type'] == null) return false;
      if (!tx.containsKey('category') || tx['category'] == null) return false;
      if (!tx.containsKey('value') && !tx.containsKey('amount')) return false;

      if (tx['periodicity'] == 'semanal') {
        if (!tx.containsKey('dayofWeek') && !tx.containsKey('day'))
          return false;
      } else if (tx['periodicity'] == 'mensal') {
        if (!tx.containsKey('day')) return false;
      }

      if (tx['type'] == 'despesa' && !tx.containsKey('budgetCategory'))
        return false;

      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        constraints: BoxConstraints(
          maxWidth: 600,
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    'Corrigir Transações com Erro',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(null),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              '${widget.errors.length} transação(ões) não foram importadas. Corrija os dados abaixo:',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.builder(
                itemCount: widget.errors.length,
                itemBuilder: (context, index) {
                  final error = widget.errors[index];
                  final errorIndex = error['index'] as int;
                  final tx = _edits[errorIndex] ??
                      Map<String, dynamic>.from(error['transaction'] as Map);
                  final errorMsg = error['error'] as String;

                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Transação ${errorIndex + 1}',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Erro: $errorMsg',
                            style: const TextStyle(
                              color: AppTheme.expenseRed,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 16),
                          // Campos editáveis - mostrar todos os campos importantes
                          _buildField(
                            'Tipo',
                            tx['type'] ?? 'despesa',
                            ['ganho', 'despesa'],
                            (value) => _updateField(errorIndex, 'type', value),
                          ),
                          _buildTextField(
                            'Categoria',
                            tx['category'] ?? '',
                            (value) =>
                                _updateField(errorIndex, 'category', value),
                          ),
                          _buildNumberField(
                            'Valor',
                            (tx['value'] ?? tx['amount'] ?? '0').toString(),
                            (value) {
                              final numValue = double.tryParse(value) ?? 0;
                              _updateField(errorIndex, 'value', numValue);
                              _updateField(errorIndex, 'amount', numValue);
                            },
                          ),
                          if (tx['periodicity'] == 'semanal')
                            _buildField(
                              'Dia da Semana',
                              (tx['dayofWeek'] ?? tx['day'] ?? 'segunda')
                                  .toString(),
                              [
                                'domingo',
                                'segunda',
                                'terça',
                                'terca',
                                'quarta',
                                'quinta',
                                'sexta',
                                'sábado',
                                'sabado'
                              ],
                              (value) {
                                _updateField(errorIndex, 'dayofWeek', value);
                                _updateField(errorIndex, 'day', value);
                              },
                            ),
                          if (tx['periodicity'] == 'mensal')
                            _buildNumberField(
                              'Dia do Mês',
                              (tx['day'] ?? '1').toString(),
                              (value) => _updateField(
                                  errorIndex, 'day', int.tryParse(value) ?? 1),
                            ),
                          if ((tx['type'] ?? 'despesa') == 'despesa')
                            _buildField(
                              'Categoria de Orçamento',
                              tx['budgetCategory'] ?? 'gastos',
                              ['gastos', 'lazer', 'poupanca'],
                              (value) => _updateField(
                                  errorIndex, 'budgetCategory', value),
                            ),
                          if (tx['description'] != null)
                            _buildTextField(
                              'Descrição',
                              tx['description'] ?? '',
                              (value) => _updateField(
                                  errorIndex, 'description', value),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(null),
                  child: const Text('Cancelar'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () {
                    final fixed = _getFixedTransactions();
                    Navigator.of(context).pop(fixed);
                  },
                  child: Text(
                      'Importar ${_getFixedTransactions().length} Corrigida(s)'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildField(String label, String value, List<String> options,
      Function(String) onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
          ),
          const SizedBox(height: 4),
          DropdownButtonFormField<String>(
            value: value,
            items: options
                .map((opt) => DropdownMenuItem(
                      value: opt,
                      child: Text(opt),
                    ))
                .toList(),
            onChanged: (val) => onChanged(val ?? value),
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField(
      String label, String value, Function(String) onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
          ),
          const SizedBox(height: 4),
          TextFormField(
            initialValue: value,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  Widget _buildNumberField(
      String label, String value, Function(String) onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
          ),
          const SizedBox(height: 4),
          TextFormField(
            initialValue: value,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _DuplicateSelectionDialog extends StatefulWidget {
  final List<Map<String, dynamic>> duplicates;
  final List<Transaction> existingTransactions;

  const _DuplicateSelectionDialog({
    required this.duplicates,
    required this.existingTransactions,
  });

  @override
  State<_DuplicateSelectionDialog> createState() =>
      _DuplicateSelectionDialogState();
}

class _DuplicateSelectionDialogState extends State<_DuplicateSelectionDialog> {
  final Set<int> _selectedIndices = {};

  String _formatTransaction(Map<String, dynamic> tx) {
    final type = tx['type'] == 'ganho' ? 'Ganho' : 'Despesa';
    final amount = tx['value'] ?? tx['amount'] ?? 0;
    final amountNum = (amount is num)
        ? amount.toDouble()
        : double.tryParse(amount.toString().replaceAll(',', '.')) ?? 0;
    final category = tx['category'] ?? '';
    final description = tx['description'] ?? '';
    final periodicity = tx['periodicity'] ?? '';

    String periodicityStr = '';
    if (periodicity == 'mensal') {
      periodicityStr = ' (Mensal, dia ${tx['day'] ?? ''})';
    } else if (periodicity == 'semanal') {
      periodicityStr = ' (Semanal, ${tx['dayofWeek'] ?? tx['day'] ?? ''})';
    }

    String desc = description.toString().isNotEmpty ? ' - $description' : '';

    return '$type: ${amountNum.toStringAsFixed(2)}€ - $category$periodicityStr$desc';
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        constraints: BoxConstraints(
          maxWidth: 600,
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Cabeçalho
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: AppTheme.white,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Transações Duplicadas',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Selecione quais deseja sobrescrever (${widget.duplicates.length} encontrada(s))',
                          style: const TextStyle(
                            fontSize: 14,
                            color: AppTheme.darkGray,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            // Lista de duplicatas
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                itemCount: widget.duplicates.length,
                itemBuilder: (context, index) {
                  final dup = widget.duplicates[index];
                  final txIndex = dup['index'] as int;
                  final tx = dup['transaction'] as Map<String, dynamic>;
                  final isSelected = _selectedIndices.contains(txIndex);

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: CheckboxListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 0),
                      title: Text(
                        _formatTransaction(tx),
                        style: const TextStyle(fontSize: 12),
                      ),
                      value: isSelected,
                      onChanged: (value) {
                        setState(() {
                          if (value == true) {
                            _selectedIndices.add(txIndex);
                          } else {
                            _selectedIndices.remove(txIndex);
                          }
                        });
                      },
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                  );
                },
              ),
            ),
            // Botões
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: AppTheme.white,
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Botões de ação rápida
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      TextButton(
                        onPressed: () {
                          setState(() {
                            _selectedIndices.clear();
                          });
                        },
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text('Pular Todas',
                            style: TextStyle(fontSize: 12)),
                      ),
                      const SizedBox(width: 16),
                      TextButton(
                        onPressed: () {
                          setState(() {
                            _selectedIndices.clear();
                            _selectedIndices.addAll(
                              widget.duplicates.map((d) => d['index'] as int),
                            );
                          });
                        },
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text('Selecionar Todas',
                            style: TextStyle(fontSize: 12)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Botão Continuar (largura total)
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () =>
                          Navigator.of(context).pop(_selectedIndices),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        minimumSize: const Size(double.infinity, 48),
                      ),
                      child: Text('Continuar (${_selectedIndices.length})',
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
