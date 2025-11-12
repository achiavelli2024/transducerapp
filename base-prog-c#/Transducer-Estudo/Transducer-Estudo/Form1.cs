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








namespace Transducer_Estudo
{
    public partial class Form1 : Form
    {
        private ITransducer Trans;

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

        private void Form1_Load(object sender, EventArgs e)
        {
            ListPorts();
        }

        private void button2_Click(object sender, EventArgs e)
        {
            string sname = drpPortName.SelectedItem.ToString();

            ConnectCom(sname);

        }

        private void ConnectCom(string sname)
        {
            tickLastUpdateTorque = 0;
            //lblUpdateTorque.Text = "0";
            //lblUpdateTemp.Text = "0";
            //lblTemp.Text = "0";
            //lblVoltage.Text = "0";

            if (Trans != null)
            {
                Trans.StopReadData();
                Trans.StopService();
            }

            //if (rdbSCS.Checked)
                //Trans = new Transducer();
            //else
            Trans = new PhoenixTransducer();
            //Trans.RaiseError += new ErrorReceiver(ErrorReceiver);
            //Trans.RaiseEvent += new EventReceiver(EventReceiver);
            //Trans.DataResult += new DataResultReceiver(ResultReceiver);
            //Trans.DataInformation += new DataInformationReceiver(InformationReceiver);
            Trans.TesteResult += new DataTesteResultReceiver(TesteResultReceiver);
            //Trans.DebugInformation += new DebugInformationReceiver(DebugReceiver);
            //Trans.CountersInformation += new CountersInformationReceiver(CountersReceiver);

            string[] s = new string[2];
            //s[0] = "1";
            //if (this.chkSimulAng.Checked)
                //s[1] = "1";

            Trans.SetPerformance(ePCSpeed.Slow, eCharPoints.Many);

            Trans.PortName = sname;
            //Trans.PortIndex = Convert.ToInt32(txtIndex.Text);
            Trans.StartService();
            Trans.StartCommunication();
            Trans.RequestInformation();
            timer1.Start();
        }

        private void btnReadData_Click(object sender, EventArgs e)
        {
            tickLastUpdateTorque = 0;

            lblAngulo.Text = "0 º";
            lblTorque.Text = "0 Nm";

            InitRead();

        }


        private void InitRead()

        {
            Debug.Print("---------- InitRead");

            Trans.SetZeroTorque();
            System.Threading.Thread.Sleep(10);
            Trans.SetZeroAngle();
            System.Threading.Thread.Sleep(10);
            Trans.SetTestParameter_ClickWrench(30, 30, 20);
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
            Trans.StartReadData();



        }




        private void InitRead2()
        {
            LogToFile("---------- InitRead");

            // Log para o SetZeroTorque
            LogToFile("Enviando comando: SetZeroTorque");
            Trans.SetZeroTorque();
            System.Threading.Thread.Sleep(10); // Atraso de 10 ms

            // Log para o SetZeroAngle
            LogToFile("Enviando comando: SetZeroAngle");
            Trans.SetZeroAngle();
            System.Threading.Thread.Sleep(10); // Atraso de 10 ms

            // Log para o SetTestParameter_ClickWrench
            LogToFile("Enviando comando: SetTestParameter_ClickWrench(30, 30, 20)");
            Trans.SetTestParameter_ClickWrench(30, 30, 20);

            // Log para o SetTestParameter
            LogToFile("Enviando comando: SetTestParameter com os seguintes parâmetros:");
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

            // Log para o StartReadData
            LogToFile("Enviando comando: StartReadData");
            Trans.StartReadData();


        }


        private void LogToFile(string message)
        {
            string logFilePath = "C:\\Users\\achia\\Centigrama\\transducer_log.txt";
            using (StreamWriter sw = new StreamWriter(logFilePath, true))
            {
                sw.WriteLine($"{DateTime.Now}: {message}");
            }
        }


        private void TesteResultReceiver(List<DataResult> Result)
        {

            Debug.Print("SHOW AT SCREEN " + System.Environment.TickCount);
            DataResult Data = Result.Where(x => x.Type == "FR").FirstOrDefault();


            if (Data == null)
            {
                lblUntighteningsCounter.BeginInvoke((MethodInvoker)delegate
                {
                    lblUntighteningsCounter.Text = (++UntighteningsCounter).ToString();
                });
                InitRead();
                return;
            }


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

            //txtGraph.BeginInvoke((MethodInvoker)delegate
            //{
                //txtGraph.Text = s;
            //});
            Debug.Print("SHOW AT SCREEN END" + System.Environment.TickCount);

            InitRead();
            Debug.Print("AFTER RECONFIG " + System.Environment.TickCount);





        }





        private void ResultReceiver(DataResult Data)
        {


            lblAngulo.BeginInvoke((MethodInvoker)delegate
            {

                lblAngulo1.Text = Data.Angle.ToString() + " º";
            });


            lblTorque.BeginInvoke((MethodInvoker)delegate
            {

                lblTorque1.Text = Data.Torque.ToString() + " Nm";

            });

            //lblTest.BeginInvoke((MethodInvoker)delegate
            //{

                //lblTest.Text = (Datainfo.TorqueLimit * Data.Torque) / 65M + " Nm";

            //});

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

        private void button3_Click(object sender, EventArgs e)
        {
            Trans.StopReadData();
            tickLastUpdateTorque = 0;
        }

        private void btnConnectIP_Click(object sender, EventArgs e)
        {
            //if (rdbSCS.Checked)
            //{
                //MessageBox.Show("Selecione o Transdutor M.Shimizu!", "Erro!");

            //}

            //else
            //{




                if (Trans != null)
                {
                    Trans.StopReadData();
                    Trans.StopService();
                }


                //if (rdbSCS.Checked)
                    //Trans = new Transducer();
                //else
                    Trans = new PhoenixTransducer();
                //Trans.RaiseError += new ErrorReceiver(ErrorReceiver);
                //Trans.RaiseEvent += new EventReceiver(EventReceiver);
                Trans.DataResult += new DataResultReceiver(ResultReceiver);
                //Trans.DataInformation += new DataInformationReceiver(InformationReceiver);
                Trans.TesteResult += new DataTesteResultReceiver(TesteResultReceiver);
                //Trans.DebugInformation += new DebugInformationReceiver(DebugReceiver);
                //Trans.CountersInformation += new CountersInformationReceiver(CountersReceiver);

            


                //string[] s = new string[2];
                //s[0] = "1";
                //if (this.chkSimulAng.Checked)
                //s[1] = "1";

                //Trans.SetTests(s);

                Trans.SetPerformance(ePCSpeed.Slow, eCharPoints.Many);

                Trans.Eth_IP = txtIP.Text;
                Trans.Eth_Port = 23;
                Trans.PortIndex = Convert.ToInt32(txtIndex.Text);
                Trans.StartService();
                Trans.StartCommunication();
                Trans.RequestInformation();
                timer1.Start();
         }

        private void btnDisconnect2_Click(object sender, EventArgs e)
        {
            btnDisconnect_Click(sender, e);
        }

        private void btnDisconnect_Click(object sender, EventArgs e)
        {
            //lblTemp.Text = "0";
            //lblVoltage.Text = "0";
            //txtKeyName.Text = "";
            //txtAutoPowerOff.Text = "";
            //txtTorqueLimit.Text = "";
            //txtFullScale.Text = "";
            //txtDeviceType.Text = "";
            //txtCommunicationType.Text = "";
            //txtFW.Text = "";
            //txtHW.Text = "";
            //txtHardID.Text = "";


            timer1.Stop();
            Trans.StopReadData();
            Trans.StopService();

            //ClearForm();
        }
    }
}
