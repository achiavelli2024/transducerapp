using System;
using System.Collections.Generic;
//using System.ComponentModel;
using System.Data;
//using System.Drawing;
using System.Linq;
//using System.Text;
//using System.Threading.Tasks;
using System.Windows.Forms;
using System.IO.Ports;
using ITransducers;
using Transducers;
using System.IO;
using System.Diagnostics;
using Transducer_Estudo;
using System.Text;



using Transducer_Estudo;

namespace Transducer_Estudo
{
    public partial class Form1 : Form
    {
        private ITransducer Trans;

        private PhoenixTransducer px;

        private DataInformation Datainfo = new DataInformation();
        //private CountersInformation Countersinfo = new CountersInformation();
        //private DebugInformation Debuginfo = new DebugInformation();
        private int ResultsCounter = 0;
        private int UntighteningsCounter = 0;
        //private string rastInfo = "";
        //int alivetime = -0;
        int tickLastUpdateTorque = 0;



        public Form1()
        {
            InitializeComponent();
        }


        private void ListPorts()
        {

            string[] Ports = SerialPort.GetPortNames();
            for (int i = 0; i < Ports.Length; i++)
            {
                drpPortName.Items.Add(Ports[i]);
            }

            if (Ports.Length > 0)
                drpPortName.SelectedIndex = 0;
        }

        // Form load: já configura o logger (você já tinha feito), adiciono log confirmando
        private void Form1_Load(object sender, EventArgs e)
        {
            ListPorts();
            // Exemplo: configurar explicitamente para C:\logs (requer permissão)
            // Descomente uma das opções abaixo conforme preferir.

            // 1) Usar C:\logs (precisa de permissão administrativa)
            // TransducerLogger.Configure(@"C:\logs", enabled: true);

            // 2) (Recomendado) usar pasta do usuário dentro AppData (sem precisar de admin)
            string appDataLogFolder = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "transducerapp", "logs");
            TransducerLogger.Configure(appDataLogFolder, enabled: true);

            // 3) (alternativa) usar temp
            // TransducerLogger.Configure(Path.Combine(Path.GetTempPath(), "transducer_debug.log"), enabled: true);

            TransducerLogger.Log("Application START - logger configured");
            TransducerLogger.LogFmt("Form1_Load - log file: {0}", TransducerLogger.FilePath);

            // Pequeno teste: escreve uma linha e verifica se o arquivo existe, então mostra um MessageBox com o caminho
            // (comentei a MessageBox para não atrapalhar execução contínua)
            //try
            //{
            //    TransducerLogger.Log("Test write after configure");
            //    string path = TransducerLogger.FilePath;
            //    bool exists = File.Exists(path);
            //    MessageBox.Show($"Logger configured. Path: {path}\nFile exists after test write: {exists}", "Logger", MessageBoxButtons.OK, MessageBoxIcon.Information);
            //}
            //catch (Exception ex)
            //{
            //    MessageBox.Show("Erro ao testar logger: " + ex.Message, "Logger error", MessageBoxButtons.OK, MessageBoxIcon.Error);
            //}
        }

        // Botão que conecta via COM (UI). Adiciona log do evento.
        private void button2_Click(object sender, EventArgs e)
        {
            string sname = drpPortName.SelectedItem.ToString();

            TransducerLogger.LogFmt("button2_Click - connect COM: {0}", sname);
            ConnectCom(sname);
        }

        // Método central de conexão via serial (usado pela UI). Adiciona logs estratégicos.
        private void ConnectCom(string sname)
        {
            tickLastUpdateTorque = 0;

            TransducerLogger.LogFmt("ConnectCom: starting connect flow for port '{0}'", sname);

            if (Trans != null)
            {
                TransducerLogger.Log("ConnectCom: stopping previous transducer (StopReadData/StopService)");
                Trans.StopReadData();
                Trans.StopService();
            }

            // cria nova instância (não mudamos a implementação)
            Trans = new PhoenixTransducer();

            // Inscreve os handlers essenciais (TestResult já estava inscrito)
            Trans.TesteResult += new DataTesteResultReceiver(TesteResultReceiver);

            // Configura performance e porta
            Trans.SetPerformance(ePCSpeed.Slow, eCharPoints.Many);
            Trans.PortName = sname;

            TransducerLogger.LogFmt("ConnectCom: calling StartService / StartCommunication / RequestInformation for port {0}", sname);
            // inicia comunicação
            Trans.StartService();
            Trans.StartCommunication();
            Trans.RequestInformation();

            TransducerLogger.Log("ConnectCom: started service and requested information");

            // inicia timer do formulário para atualizar UI (comportamento original)
            timer1.Start();

            TransducerLogger.Log("ConnectCom: timer1 started");
        }

        // Substitua no arquivo do seu Form (onde btnReadData_Click está definido)
        private void btnReadData_Click(object sender, EventArgs e)
        {
            tickLastUpdateTorque = 0;

            lblAngulo.Text = "0 º";
            lblTorque.Text = "0 Nm";

            TransducerLogger.Log("btnReadData_Click - calling InitRead()");

            // --- NOVO: gravação no log de protocolo por sessão (pré-envio dos payloads de InitRead) ---
            try
            {
                ProtocolFileLogger.WriteProtocol("SYS", "UI BUTTON: btnReadData clicked by user", null);

                // Se a sua Form tem uma instância do PhoenixTransducer, use-a para obter os payloads
                if (this.Trans != null)
                {
                    try
                    {
                        //var payloads = this.Trans.GetInitReadPayloads();
                        var payloads = this.Trans.GetInitReadFrames();


                        foreach (var p in payloads)
                        {
                            string ascii = p.Item1;
                            byte[] bytes = p.Item2;

                            // Grava payload ASCII e os bytes correspondentes (pré-CRC)
                            ProtocolFileLogger.WriteProtocol("TX (pre-CRC)", ascii, bytes);

                            // Também logue em TransducerLogger para console/debug
                            TransducerLogger.LogFmt("btnReadData: planned payload (pre-CRC): {0}", ascii);
                            TransducerLogger.LogHex("btnReadData: planned payload bytes", bytes, 0, bytes.Length);
                        }
                    }
                    catch (Exception ex)
                    {
                        TransducerLogger.LogException(ex, "btnReadData: GetInitReadPayloads logging failed");
                    }
                }
                else
                {
                    // Se não houver instância disponível aqui, apenas registre aviso (não interrompe)
                    ProtocolFileLogger.WriteProtocol("SYS", "PhoenixTransducer instance not available at btnReadData (pre-CRC payloads not logged)", null);
                    TransducerLogger.Log("btnReadData: PhoenixTransducer instance is null - cannot fetch planned payloads");
                }
            }
            catch (Exception ex)
            {
                TransducerLogger.LogException(ex, "ProtocolFileLogger write error in btnReadData_Click");
            }

            // Chama InitRead (o PhoenixTransducer fará os envios reais e logs do SendCommand)
            InitRead();
        }





        // InitRead: rotina que prepara a sequência ZO/CS/SA e inicia leitura.
        // Adicionamos logs antes das chamadas que disparam comandos no transdutor.
        private void InitRead()
        {
            Debug.Print("---------- InitRead");

            // Log antes de cada ação para correlacionar com TX no C#
            TransducerLogger.Log("InitRead: SetZeroTorque");
            Trans.SetZeroTorque();
            System.Threading.Thread.Sleep(10);

            TransducerLogger.Log("InitRead: SetZeroAngle");
            Trans.SetZeroAngle();
            System.Threading.Thread.Sleep(10);

            TransducerLogger.Log("InitRead: SetTestParameter_ClickWrench(30,30,20)");
            Trans.SetTestParameter_ClickWrench(30, 30, 20);

            TransducerLogger.Log("InitRead: SetTestParameter (full)");
            Trans.SetTestParameter(Datainfo,
                TesteType.TorqueOnly,
                ToolType.ToolType1,
                4M,
                Convert.ToDecimal(txtThresholdIniFree.Text),
                Convert.ToDecimal(txtThresholdEndFree.Text),
                Convert.ToInt32(txtTimeoutFree.Text),
                1,
                500,
                eDirection.CW,
                Convert.ToDecimal(txtNominalTorque.Text),
                Convert.ToDecimal(txtMinimumTorque.Text),
                Convert.ToDecimal(txtMaximoTorque.Text),
                100M,
                10M,
                300M,
                50,
                50);

            System.Threading.Thread.Sleep(100);

            TransducerLogger.Log("InitRead: calling StartReadData");
            Trans.StartReadData();
            TransducerLogger.Log("InitRead: StartReadData called");
        }

        // (Você tinha uma rotina alternativa InitRead2 com LogToFile) Mantive porém adicionei TransducerLogger
        private void InitRead2()
        {
            LogToFile("---------- InitRead");

            TransducerLogger.Log("InitRead2: Enviando comando: SetZeroTorque");
            LogToFile("Enviando comando: SetZeroTorque");
            Trans.SetZeroTorque();
            System.Threading.Thread.Sleep(10); // Atraso de 10 ms

            TransducerLogger.Log("InitRead2: Enviando comando: SetZeroAngle");
            LogToFile("Enviando comando: SetZeroAngle");
            Trans.SetZeroAngle();
            System.Threading.Thread.Sleep(10); // Atraso de 10 ms

            TransducerLogger.Log("InitRead2: Enviando comando: SetTestParameter_ClickWrench(30,30,20)");
            LogToFile("Enviando comando: SetTestParameter_ClickWrench(30, 30, 20)");
            Trans.SetTestParameter_ClickWrench(30, 30, 20);

            LogToFile("Enviando comando: SetTestParameter com os seguintes parâmetros:");
            TransducerLogger.Log("InitRead2: Enviando comando: SetTestParameter (parameters logged to file)");
            LogToFile($"Datainfo: {Datainfo}");
            LogToFile($"TesteType: {TesteType.TorqueOnly}");
            LogToFile($"ToolType: {ToolType.ToolType1}");
            LogToFile($"ThresholdIni: {Convert.ToDecimal(txtThresholdIni.Text)}");
            LogToFile($"ThresholdEnd: {Convert.ToDecimal(txtThresholdEnd.Text)}");
            LogToFile($"TimeoutEnd_ms: {Convert.ToInt32(txtTimeoutEnd.Text)}");
            LogToFile($"TimeStep_ms: 1");
            LogToFile($"FilterFrequency: 500");
            LogToFile($"Direction: eDirection.CW");
            LogToFile($"TorqueTarget: 8.1M");
            LogToFile($"TorqueMin: 7M");
            LogToFile($"TorqueMax: 10M");
            LogToFile($"AngleTarget: 100M");
            LogToFile($"AngleMin: 10M");
            LogToFile($"AngleMax: 300M");
            LogToFile($"DelayToDetectFirstPeak_ms: 50");
            LogToFile($"TimeToIgnoreNewPeak_AfterFinalThreshold_ms: 50");

            Trans.SetTestParameter(
                Datainfo,
                TesteType.TorqueOnly,
                ToolType.ToolType1,
                4M,
                Convert.ToDecimal(txtThresholdIni.Text),
                Convert.ToDecimal(txtThresholdEnd.Text),
                Convert.ToInt32(txtTimeoutEnd.Text),
                1,
                500,
                eDirection.CW,
                8.1M,
                7M,
                10M,
                100M,
                10M,
                300M,
                50,
                50);

            System.Threading.Thread.Sleep(100); // Atraso de 100 ms

            LogToFile("Enviando comando: StartReadData");
            TransducerLogger.Log("InitRead2: Enviando comando: StartReadData");
            Trans.StartReadData();
        }


        // Método auxiliar de log em arquivo que você já tem. Mantive.
        private void LogToFile(string message)
        {
            string logFilePath = "C:\\Users\\achia\\Centigrama\\transducer_log.txt";
            try
            {
                using (StreamWriter sw = new StreamWriter(logFilePath, true))
                {
                    sw.WriteLine($"{DateTime.Now}: {message}");
                }
            }
            catch (Exception ex)
            {
                TransducerLogger.LogException(ex, "LogToFile error");
            }
        }


        // Recebe os resultados de teste (lista de DataResult) - adicionamos logs sobre o resultado final (FR)
        private void TesteResultReceiver(List<DataResult> Result)
        {
            TransducerLogger.LogFmt("TesteResultReceiver called - results count: {0}", Result?.Count ?? 0);
            Debug.Print("SHOW AT SCREEN " + System.Environment.TickCount);
            DataResult Data = Result.Where(x => x.Type == "FR").FirstOrDefault();

            if (Data == null)
            {
                TransducerLogger.Log("TesteResultReceiver: no 'FR' result found - triggering InitRead again");
                lblUntighteningsCounter.BeginInvoke((MethodInvoker)delegate
                {
                    lblUntighteningsCounter.Text = (++UntighteningsCounter).ToString();
                });
                InitRead();
                return;
            }

            // Loga o resultado final encontrado
            TransducerLogger.LogFmt("TesteResultReceiver: FR result - Torque={0} Angle={1}", Data.Torque, Data.Angle);

            lblResultsCounter.BeginInvoke((MethodInvoker)delegate
            {
                lblResultsCounter.Text = (++ResultsCounter).ToString();
            });

            lblAngulo.BeginInvoke((MethodInvoker)delegate
            {
                lblAngulo.Text = Data.Angle.ToString() + "º";
            });

            lblTorque.BeginInvoke((MethodInvoker)delegate
            {
                lblTorque.Text = Data.Torque.ToString() + "Nm";
            });

            string s = "";
            for (int i = 0; i < Result.Count; i++)
            {
                s += (Result[i].Torque.ToString() + "\r\n");
            }

            Debug.Print("SHOW AT SCREEN END" + System.Environment.TickCount);

            InitRead();
            Debug.Print("AFTER RECONFIG " + System.Environment.TickCount);
        }





        // Recebe DataResult (cada TQ) - adicionamos logs para acompanhar frequência e valores
        private void ResultReceiver(DataResult Data)
        {
            TransducerLogger.LogFmt("ResultReceiver called - Torque={0} Angle={1}", Data.Torque, Data.Angle);

            lblAngulo.BeginInvoke((MethodInvoker)delegate
            {
                lblAngulo1.Text = Data.Angle.ToString() + " º";
            });

            lblTorque.BeginInvoke((MethodInvoker)delegate
            {
                lblTorque1.Text = Data.Torque.ToString() + " Nm";
            });

            lblUpdateTorque.BeginInvoke((MethodInvoker)delegate
            {
                lblUpdateTorque.Text = (Convert.ToUInt64(lblUpdateTorque.Text) + 1).ToString();
            });
            if (tickLastUpdateTorque != 0)
            {
                int j = System.Environment.TickCount - tickLastUpdateTorque;
                lblUpdateTorqueSpan.BeginInvoke((MethodInvoker)delegate
                {
                    lblUpdateTorqueSpan.Text = (j).ToString();
                });
            }
            Debug.Print("tq:" + Data.Torque.ToString("F2") + " " + System.Environment.TickCount + " span:" + (System.Environment.TickCount - tickLastUpdateTorque));
            tickLastUpdateTorque = System.Environment.TickCount;
        }

        // Botão para parar leitura: adiciona log
        private void button3_Click(object sender, EventArgs e)
        {
            TransducerLogger.Log("button3_Click - StopReadData called");
            Trans.StopReadData();
            tickLastUpdateTorque = 0;
        }

        // Botão conectar via IP / TCP - adicionamos logs
        private void btnConnectIP_Click(object sender, EventArgs e)
        {
            TransducerLogger.Log("btnConnectIP_Click - starting IP connection flow");
            //ProtocolFileLogger.WriteProtocol()

            if (Trans != null)
                
            {
                TransducerLogger.Log("btnConnectIP_Click - stopping previous transducer (StopReadData/StopService)");
                Trans.StopReadData();
                Trans.StopService();
            }

            Trans = new PhoenixTransducer();
            Trans.DataResult += new DataResultReceiver(ResultReceiver);
            Trans.TesteResult += new DataTesteResultReceiver(TesteResultReceiver);

            Trans.SetPerformance(ePCSpeed.Slow, eCharPoints.Many);

            Trans.Eth_IP = txtIP.Text;
            // OBS: Eth_Port tem apenas 'set' no PhoenixTransducer, não tem 'get' — por isso usamos um literal/variável aqui
            Trans.Eth_Port = 23;
            Trans.PortIndex = Convert.ToInt32(txtIndex.Text);

            // ERRO anterior: você tentou ler Trans.Eth_IP / Trans.Eth_Port aqui, mas propriedades são write-only.
            // Em vez disso, registremos os valores disponíveis no formulário.
            TransducerLogger.LogFmt("btnConnectIP_Click - connecting to IP {0}:{1}", txtIP.Text, 23);

            Trans.StartService();
            Trans.StartCommunication();
            Trans.RequestInformation();

            TransducerLogger.Log("btnConnectIP_Click - started service, requested info, timer started");
            timer1.Start();

            try
            {
                // Mensagem textual que será gravada no arquivo de protocolo
                string protoMsg = "UI BUTTON: btnConnectIP clicked by user";

                // Escreve no arquivo de protocolo (texto + sem bytes)
                ProtocolFileLogger.WriteProtocol("SYS", protoMsg, null);

            }
            catch (Exception ex)
            {
                // Não deixe uma falha de logging interromper a UI
                TransducerLogger.LogException(ex, "ProtocolFileLogger write error in btnConnectIP_Click");
            }




        }



        // Botão desconectar - log
        private void btnDisconnect2_Click(object sender, EventArgs e)
        {
            btnDisconnect_Click(sender, e);


            try
            {
                // Mensagem textual que será gravada no arquivo de protocolo
                string protoMsg = "UI BUTTON: btnDisconnect clicked by user";

                // Escreve no arquivo de protocolo (texto + sem bytes)
                ProtocolFileLogger.WriteProtocol("SYS", protoMsg, null);

            }
            catch (Exception ex)
            {
                // Não deixe uma falha de logging interromper a UI
                TransducerLogger.LogException(ex, "ProtocolFileLogger write error in btnDisconnect_Click");
            }






        }

        private void btnDisconnect_Click(object sender, EventArgs e)
        {
            TransducerLogger.Log("btnDisconnect_Click - stopping timer, StopReadData and StopService");
            timer1.Stop();
            if (Trans != null)
            {
                Trans.StopReadData();
                Trans.StopService();
            }

            //ClearForm();
        }

        private void timer1_Tick(object sender, EventArgs e)
        {

            //TransducerLogger.Log("Log dentro do timer");
            //TransducerLogger.LogFmt("Timer tick at {0}", DateTime.Now.ToString("HH:mm:ss.fff"));

        }
    }
}