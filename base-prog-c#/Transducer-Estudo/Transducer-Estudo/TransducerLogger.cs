using System;
using System.IO;
using System.Text;

namespace Transducer_Estudo
{
    /// <summary>
    /// Logger simples, thread-safe, escrito para arquivo e Debug.Print (modo DEBUG).
    /// - Configure o caminho se necessário usando TransducerLogger.Configure(path).
    /// - Ative/desative com TransducerLogger.Enabled.
    /// - Aceita tanto "C:\logs" (diretório) quanto "C:\logs\meuarquivo.log" (arquivo).
    /// </summary>
    internal static class TransducerLogger
    {
        private static readonly object _lock = new object();

        // Caminho padrão do arquivo de log (arquivo completo)
        private static string _filePath = Path.Combine(Path.GetTempPath(), "transducer_debug.log");

        // Ativa/desativa log
        public static bool Enabled { get; set; } = true;

        /// <summary>
        /// Retorna o caminho do arquivo de log atualmente configurado.
        /// Use para depuração (ex.: mostrar no MessageBox).
        /// </summary>
        public static string FilePath
        {
            get
            {
                lock (_lock) { return _filePath; }
            }
        }

        /// <summary>
        /// Configura caminho do arquivo de log e se está ativado.
        /// Pode receber um diretório (ex: C:\logs) ou um arquivo completo (ex: C:\logs\transducer_debug.log).
        /// Use antes de iniciar a comunicação, se quiser outro local.
        /// </summary>
        public static void Configure(string pathOrDirectory, bool enabled = true)
        {
            lock (_lock)
            {
                try
                {
                    if (string.IsNullOrWhiteSpace(pathOrDirectory))
                    {
                        // mantém o padrão
                    }
                    else
                    {
                        string candidate = pathOrDirectory;

                        // Se foi passado um diretório (termina com separator ou não contém extensão),
                        // convertemos para um arquivo dentro desse diretório.
                        bool looksLikeDirectory = false;
                        try
                        {
                            // Se path termina com separador, certamente é diretório
                            if (candidate.EndsWith(Path.DirectorySeparatorChar.ToString()) || candidate.EndsWith(Path.AltDirectorySeparatorChar.ToString()))
                                looksLikeDirectory = true;
                            // Se não tem extensão (.log etc) e não tem nome de arquivo, tratamos como diretório
                            else
                            {
                                string name = Path.GetFileName(candidate);
                                if (string.IsNullOrEmpty(name) || !name.Contains("."))
                                    looksLikeDirectory = true;
                            }
                        }
                        catch { looksLikeDirectory = false; }

                        if (looksLikeDirectory)
                        {
                            // cria um arquivo padrão dentro do diretório
                            candidate = Path.Combine(candidate, "transducer_debug.log");
                        }

                        _filePath = candidate;
                    }

                    Enabled = enabled;

                    var dir = Path.GetDirectoryName(_filePath);
                    if (!string.IsNullOrEmpty(dir) && !Directory.Exists(dir))
                        Directory.CreateDirectory(dir);
                }
                catch
                {
                    // Não lançar: falhas aqui não devem quebrar app. Enable fica como configurado.
                }
            }
        }

        /// <summary>
        /// Escreve uma linha no log (time-stamped). Thread-safe.
        /// </summary>
        public static void Log(string message)
        {
            if (!Enabled) return;
            try
            {
                var line = $"{DateTime.Now:yyyy-MM-dd HH:mm:ss.fff} {message}";
                lock (_lock)
                {
                    // AppendAllText cria o arquivo se não existir
                    File.AppendAllText(_filePath, line + Environment.NewLine, Encoding.UTF8);
                }
#if DEBUG
                try { System.Diagnostics.Debug.Print(line); } catch { }
#endif
            }
            catch (Exception ex)
            {
                // não lançar, mas logue no Debug para dev
                try { System.Diagnostics.Debug.Print("TransducerLogger.WriteError: " + ex.Message); } catch { }
            }
        }

        /// <summary>
        /// Formata e escreve no log.
        /// </summary>
        public static void LogFmt(string fmt, params object[] args)
        {
            try
            {
                Log(string.Format(fmt, args));
            }
            catch { /* ignore formatting errors */ }
        }

        /// <summary>
        /// Log de exceção completa (inclui stacktrace).
        /// </summary>
        public static void LogException(Exception ex, string prefix = null)
        {
            if (!Enabled) return;
            try
            {
                var msg = (prefix != null ? prefix + " - " : "") + ex.ToString();
                Log(msg);
            }
            catch { }
        }

        /// <summary>
        /// Dump hex simples de um buffer (útil para ver pacotes brutos).
        /// </summary>
        public static void LogHex(string tag, byte[] buffer, int offset = 0, int count = -1)
        {
            if (!Enabled) return;
            try
            {
                if (buffer == null)
                {
                    Log($"{tag}: null");
                    return;
                }
                if (count < 0) count = Math.Max(0, buffer.Length - offset);
                var sb = new StringBuilder();
                for (int i = 0; i < count; i++)
                {
                    sb.Append(buffer[offset + i].ToString("X2"));
                    if (i % 16 == 15) sb.Append(" ");
                }
                Log($"{tag}: len={count} hex={sb}");
            }
            catch { }
        }
    }
}